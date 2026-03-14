defmodule Keiro.Eng.ClaudeCli do
  @moduledoc """
  Subprocess wrapper for Claude Code (`claude --print`).

  Configurable via `CLAUDE_BIN_PATH` env or application config `:claude_bin_path`.

  The default timeout is 600,000 ms (10 minutes) and can be overridden via the
  `CLAUDE_TIMEOUT_MS` environment variable or the `:timeout` option.
  """

  require Logger

  @default_allowed_tools "Edit,Read,Write,Bash,Glob,Grep"
  @default_max_turns "50"
  @default_timeout_ms 600_000

  @doc """
  Resolve the claude binary path from config/env.
  """
  @spec claude_path() :: String.t()
  def claude_path do
    System.get_env("CLAUDE_BIN_PATH") ||
      Application.get_env(:keiro, :claude_bin_path, "claude")
  end

  @doc """
  Run Claude Code in non-interactive `--print` mode.

  Sends `prompt` to Claude Code as a subprocess, working in `repo_path`.

  Options:
  - `:timeout` — subprocess timeout in ms (default: 600_000; also reads `CLAUDE_TIMEOUT_MS` env)
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
    timeout = Keyword.get(opts, :timeout, default_timeout())
    allowed_tools = Keyword.get(opts, :allowed_tools, @default_allowed_tools)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)

    args = [
      "--print",
      "-p",
      prompt,
      "--output-format",
      "json",
      "--allowedTools",
      allowed_tools,
      "--max-turns",
      to_string(max_turns),
      "--permission-mode",
      "bypassPermissions"
    ]

    Logger.info("ClaudeCli: running in #{repo_path} (timeout: #{timeout}ms)")

    try do
      port =
        Port.open({:spawn_executable, bin}, [
          :binary,
          :exit_status,
          {:args, args},
          {:cd, repo_path}
        ])

      deadline = System.monotonic_time(:millisecond) + timeout

      case collect_port_output(port, [], deadline) do
        {:done, output, 0} ->
          parse_result(output)

        {:done, output, code} ->
          {:error, "claude exited with code #{code}: #{String.slice(output, 0, 500)}"}

        {:timeout, _partial} ->
          kill_port_process(port, timeout)
          {:error, "claude timed out after #{timeout}ms"}
      end
    rescue
      e in ErlangError -> {:error, "claude CLI not found: #{inspect(e)}"}
    end
  end

  # Reads data from the port until the process exits or the deadline passes.
  # Uses deadline (absolute monotonic ms) so recursive calls don't reset the timer.
  defp collect_port_output(port, chunks, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, data}} ->
        collect_port_output(port, [chunks | [data]], deadline)

      {^port, {:exit_status, code}} ->
        {:done, IO.iodata_to_binary(chunks), code}
    after
      remaining ->
        {:timeout, IO.iodata_to_binary(chunks)}
    end
  end

  # Kills the OS process backing the port so we don't leave orphaned claude
  # subprocesses running after Elixir declares a timeout.
  defp kill_port_process(port, timeout) do
    case :erlang.port_info(port, :os_pid) do
      {:os_pid, os_pid} ->
        Logger.warning("ClaudeCli: killing OS PID #{os_pid} after #{timeout}ms timeout")
        System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)

      _ ->
        :ok
    end

    Port.close(port)
  end

  defp default_timeout do
    case System.get_env("CLAUDE_TIMEOUT_MS") do
      nil ->
        @default_timeout_ms

      val ->
        case Integer.parse(val) do
          {ms, ""} when ms > 0 -> ms
          _ -> @default_timeout_ms
        end
    end
  end

  defp parse_result(stdout) do
    case Jason.decode(stdout) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:ok, other} ->
        {:ok, %{"result" => other}}

      {:error, _reason} ->
        # Fallback: treat raw stdout as the result text
        {:ok, %{"result" => String.trim(stdout), "parse_error" => true}}
    end
  end
end
