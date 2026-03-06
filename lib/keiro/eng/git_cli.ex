defmodule Keiro.Eng.GitCli do
  @moduledoc """
  Shared subprocess wrapper for the `git` CLI.

  Configurable via `GIT_BIN_PATH` env or application config `:git_bin_path`.
  """

  @type run_opts :: [cd: String.t()]

  @doc """
  Resolve the git binary path from config/env.
  """
  @spec git_path() :: String.t()
  def git_path do
    System.get_env("GIT_BIN_PATH") ||
      Application.get_env(:keiro, :git_bin_path, "git")
  end

  @doc """
  Run a git CLI command with the given arguments.

  Options:
  - `:cd` — working directory
  """
  @spec run(String.t(), [String.t()], run_opts()) :: {:ok, String.t()} | {:error, String.t()}
  def run(git_bin, args, opts \\ []) do
    cmd_opts =
      [stderr_to_stdout: true]
      |> maybe_put_cd(opts)

    case System.cmd(git_bin, args, cmd_opts) do
      {stdout, 0} -> {:ok, String.trim(stdout)}
      {output, _code} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError ->
      {:error, "git CLI not found: #{inspect(e)}"}
  end

  defp maybe_put_cd(cmd_opts, opts) do
    case Keyword.get(opts, :cd) do
      nil -> cmd_opts
      dir -> Keyword.put(cmd_opts, :cd, dir)
    end
  end
end
