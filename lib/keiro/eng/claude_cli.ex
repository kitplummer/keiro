defmodule Keiro.Eng.ClaudeCli do
  @moduledoc """
  Subprocess wrapper for Claude Code (`claude --print`).

  Configurable via `CLAUDE_BIN_PATH` env or application config `:claude_bin_path`.
  """

  require Logger

  @default_allowed_tools "Edit,Read,Write,Bash,Glob,Grep"
  @default_max_turns "50"

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
  - `:timeout` — subprocess timeout in ms (default: 300_000)
  - `:allowed_tools` — comma-separated tool list (default: "Edit,Read,Write,Bash,Glob,Grep")
  - `:max_turns` — max agentic turns (default: "50")

  Returns `{:ok, result_map}` on success or `{:error, reason}` on failure.
  """
  @spec run(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(prompt, repo_path, opts \\ []) do
    bin = Keyword.get(opts, :bin, claude_path())
    timeout = Keyword.get(opts, :timeout, 300_000)
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

    task =
      Task.async(fn ->
        try do
          {:cmd, System.cmd(bin, args, cd: repo_path, stderr_to_stdout: false)}
        rescue
          e in ErlangError -> {:error, "claude CLI not found: #{inspect(e)}"}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:cmd, {stdout, 0}}} ->
        parse_result(stdout)

      {:ok, {:cmd, {stdout, code}}} ->
        {:error, "claude exited with code #{code}: #{String.slice(stdout, 0, 500)}"}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, "claude timed out after #{timeout}ms"}
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
