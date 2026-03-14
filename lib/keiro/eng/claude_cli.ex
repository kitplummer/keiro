defmodule Keiro.Eng.ClaudeCli do
  @moduledoc """
  Subprocess wrapper for Claude Code (`claude --print`).

  Configurable via `CLAUDE_BIN_PATH` env or application config `:claude_bin_path`.

  Uses `--output-format stream-json` for real-time NDJSON events. Each event
  resets the idle timer, so Claude can work for as long as it needs as long as
  it's making progress (reading files, writing code, running tests). A hard
  `:max_timeout` cap prevents runaway sessions.
  """

  require Logger

  @default_allowed_tools "Edit,Read,Write,Bash,Glob,Grep"
  @default_max_turns "50"
  @default_idle_timeout_ms 120_000
  @default_max_timeout_ms 1_800_000

  @doc """
  Resolve the claude binary path from config/env.
  """
  @spec claude_path() :: String.t()
  def claude_path do
    System.get_env("CLAUDE_BIN_PATH") ||
      Application.get_env(:keiro, :claude_bin_path, "claude")
  end

  @doc """
  Run Claude Code in non-interactive `--print` mode with streaming JSON output.

  Sends `prompt` to Claude Code as a subprocess, working in `repo_path`.

  Options:
  - `:idle_timeout` — max ms between output chunks before declaring idle
    (default: 120_000 = 2 min; also reads `CLAUDE_IDLE_TIMEOUT_MS` env)
  - `:max_timeout` — absolute cap on total runtime in ms
    (default: 1_800_000 = 30 min; also reads `CLAUDE_MAX_TIMEOUT_MS` env)
  - `:timeout` — legacy alias for `:idle_timeout` (backward compat)
  - `:allowed_tools` — comma-separated tool list (default: "Edit,Read,Write,Bash,Glob,Grep")
  - `:max_turns` — max agentic turns (default: "50")

  Returns `{:ok, result_map}` on success or `{:error, reason}` on failure.

  Uses Port-based process management so that the OS subprocess is properly
  killed when the timeout fires, preventing orphaned claude processes from
  continuing to run (and create branches/PRs) after Elixir has declared failure.
  """
  @spec run(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(prompt, repo_path, opts \\ []) do
    bin = Keyword.get(opts, :bin, claude_path())

    idle_timeout =
      Keyword.get(opts, :idle_timeout) ||
        Keyword.get(opts, :timeout) ||
        default_idle_timeout()

    max_timeout = Keyword.get(opts, :max_timeout, default_max_timeout())
    allowed_tools = Keyword.get(opts, :allowed_tools, @default_allowed_tools)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)

    args = [
      "--print",
      "-p",
      prompt,
      "--output-format",
      "stream-json",
      "--verbose",
      "--allowedTools",
      allowed_tools,
      "--max-turns",
      to_string(max_turns),
      "--permission-mode",
      "bypassPermissions"
    ]

    Logger.info(
      "ClaudeCli: running in #{repo_path} (idle_timeout: #{idle_timeout}ms, max: #{max_timeout}ms)"
    )

    try do
      port =
        Port.open({:spawn_executable, bin}, [
          :binary,
          :exit_status,
          {:args, args},
          {:cd, repo_path}
        ])

      deadline = System.monotonic_time(:millisecond) + max_timeout

      case collect_port_output(port, [], idle_timeout, deadline) do
        {:done, output, 0} ->
          parse_stream_result(output)

        {:done, output, code} ->
          {:error, "claude exited with code #{code}: #{String.slice(output, 0, 500)}"}

        {:idle_timeout, _partial} ->
          kill_port_process(port, "idle #{idle_timeout}ms")
          {:error, "claude idle for #{idle_timeout}ms (no output), killed"}

        {:max_timeout, _partial} ->
          kill_port_process(port, "max #{max_timeout}ms")
          {:error, "claude hit max timeout of #{max_timeout}ms, killed"}
      end
    rescue
      e in ErlangError -> {:error, "claude CLI not found: #{inspect(e)}"}
    end
  end

  # Reads data from the port until the process exits, idle timeout fires,
  # or absolute deadline passes. Each chunk of output resets the idle timer.
  defp collect_port_output(port, chunks, idle_timeout, deadline) do
    now = System.monotonic_time(:millisecond)
    remaining_max = max(0, deadline - now)
    wait = min(idle_timeout, remaining_max)

    if remaining_max <= 0 do
      {:max_timeout, IO.iodata_to_binary(chunks)}
    else
      receive do
        {^port, {:data, data}} ->
          collect_port_output(port, [chunks | [data]], idle_timeout, deadline)

        {^port, {:exit_status, code}} ->
          {:done, IO.iodata_to_binary(chunks), code}
      after
        wait ->
          if wait < idle_timeout do
            {:max_timeout, IO.iodata_to_binary(chunks)}
          else
            {:idle_timeout, IO.iodata_to_binary(chunks)}
          end
      end
    end
  end

  # Kills the OS process backing the port so we don't leave orphaned claude
  # subprocesses running after Elixir declares a timeout.
  defp kill_port_process(port, reason) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} ->
        Logger.warning("ClaudeCli: killing OS PID #{os_pid} (#{reason})")
        System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)

      _ ->
        :ok
    end

    Port.close(port)
  end

  defp default_idle_timeout do
    read_env_int("CLAUDE_IDLE_TIMEOUT_MS") ||
      read_env_int("CLAUDE_TIMEOUT_MS") ||
      @default_idle_timeout_ms
  end

  defp default_max_timeout do
    read_env_int("CLAUDE_MAX_TIMEOUT_MS") || @default_max_timeout_ms
  end

  defp read_env_int(var) do
    case System.get_env(var) do
      nil -> nil
      val -> parse_pos_int(val)
    end
  end

  defp parse_pos_int(val) do
    case Integer.parse(val) do
      {ms, ""} when ms > 0 -> ms
      _ -> nil
    end
  end

  @doc """
  Parse NDJSON stream output from `claude --print --output-format stream-json`.

  Extracts the final `{"type":"result",...}` event and normalizes it to the
  same shape as the old `--output-format json` output for backward compat.
  """
  def parse_stream_result(output) do
    lines =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Parse all NDJSON events
    events =
      Enum.flat_map(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => _} = event} -> [event]
          _ -> []
        end
      end)

    # Find the result event (last one with type "result")
    result_event =
      events
      |> Enum.reverse()
      |> Enum.find(&(&1["type"] == "result"))

    case result_event do
      %{"subtype" => "success"} = evt ->
        {:ok, normalize_result(evt)}

      %{"is_error" => true} = evt ->
        {:error, evt["result"] || "claude returned an error"}

      %{} = evt ->
        # Result event exists but may not have subtype — check is_error
        if evt["is_error"] do
          {:error, evt["result"] || "claude returned an error"}
        else
          {:ok, normalize_result(evt)}
        end

      nil ->
        # No result event found — try legacy single-JSON parse as fallback
        parse_legacy_result(output)
    end
  end

  defp normalize_result(evt) do
    %{
      "result" => evt["result"],
      "cost_usd" => evt["total_cost_usd"],
      "duration_ms" => evt["duration_ms"],
      "num_turns" => evt["num_turns"],
      "session_id" => evt["session_id"],
      "usage" => evt["usage"]
    }
  end

  # Fallback for non-stream output (mock scripts, legacy usage)
  defp parse_legacy_result(output) do
    case Jason.decode(output) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:ok, other} ->
        {:ok, %{"result" => other}}

      {:error, _} ->
        extract_json_from_mixed_output(output)
    end
  end

  defp extract_json_from_mixed_output(output) do
    lines = String.split(output, "\n")

    result =
      lines
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        trimmed = String.trim(line)

        if String.starts_with?(trimmed, "{") do
          case Jason.decode(trimmed) do
            {:ok, map} when is_map(map) -> {:ok, map}
            _ -> nil
          end
        end
      end)

    case result do
      {:ok, map} -> {:ok, map}
      nil -> {:ok, %{"result" => String.trim(output), "parse_error" => true}}
    end
  end
end
