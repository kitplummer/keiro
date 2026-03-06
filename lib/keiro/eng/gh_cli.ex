defmodule Keiro.Eng.GhCli do
  @moduledoc """
  Shared subprocess wrapper for the `gh` CLI (GitHub).

  Configurable via `GH_BIN_PATH` env or application config `:gh_bin_path`.
  """

  @type run_opts :: [cd: String.t()]

  @doc """
  Resolve the gh binary path from config/env.
  """
  @spec gh_path() :: String.t()
  def gh_path do
    System.get_env("GH_BIN_PATH") ||
      Application.get_env(:keiro, :gh_bin_path, "gh")
  end

  @doc """
  Run a gh CLI command with the given arguments.

  Options:
  - `:cd` — working directory
  """
  @spec run(String.t(), [String.t()], run_opts()) :: {:ok, String.t()} | {:error, String.t()}
  def run(gh_bin, args, opts \\ []) do
    cmd_opts =
      [stderr_to_stdout: true]
      |> maybe_put_cd(opts)

    case System.cmd(gh_bin, args, cmd_opts) do
      {stdout, 0} -> {:ok, String.trim(stdout)}
      {output, _code} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError ->
      {:error, "gh CLI not found: #{inspect(e)}"}
  end

  defp maybe_put_cd(cmd_opts, opts) do
    case Keyword.get(opts, :cd) do
      nil -> cmd_opts
      dir -> Keyword.put(cmd_opts, :cd, dir)
    end
  end
end
