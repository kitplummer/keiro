defmodule Keiro.Ops.FlyCli do
  @moduledoc """
  Shared subprocess wrapper for the `fly` CLI.

  Configurable via `FLY_BIN_PATH` env or application config `:fly_bin_path`.
  """

  @type run_opts :: [cd: String.t()]

  @doc """
  Resolve the fly binary path from config/env.
  """
  @spec fly_path() :: String.t()
  def fly_path do
    System.get_env("FLY_BIN_PATH") ||
      Application.get_env(:keiro, :fly_bin_path, "~/.fly/bin/fly")
      |> expand_path()
  end

  @doc """
  Run a fly CLI command with the given arguments.

  Options:
  - `:cd` — working directory
  """
  @spec run(String.t(), [String.t()], run_opts()) :: {:ok, String.t()} | {:error, String.t()}
  def run(fly_bin, args, opts \\ []) do
    cmd_opts =
      [stderr_to_stdout: true]
      |> maybe_put_cd(opts)

    case System.cmd(fly_bin, args, cmd_opts) do
      {stdout, 0} -> {:ok, String.trim(stdout)}
      {output, _code} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError ->
      {:error, "fly CLI not found: #{inspect(e)}"}
  end

  defp expand_path("~/" <> rest), do: Path.join(System.user_home!(), rest)
  defp expand_path(path), do: path

  defp maybe_put_cd(cmd_opts, opts) do
    case Keyword.get(opts, :cd) do
      nil -> cmd_opts
      dir -> Keyword.put(cmd_opts, :cd, dir)
    end
  end
end
