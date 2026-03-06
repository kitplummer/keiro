defmodule Keiro.Beads.Client do
  @moduledoc """
  Wraps the `bd` CLI for Beads task graph operations.

  Same pattern as GLITCHLAB's Rust BeadsClient — subprocess calls to `bd`.

  ## Usage

      client = Keiro.Beads.Client.new("/path/to/repo")
      {:ok, beads} = Keiro.Beads.Client.list(client)
      {:ok, _} = Keiro.Beads.Client.create(client, "Fix crash-loop", priority: 0, type: "bug")
  """

  alias Keiro.Beads.Bead

  @type t :: %__MODULE__{
          repo_path: String.t(),
          bd_path: String.t()
        }

  defstruct [:repo_path, :bd_path]

  @doc """
  Create a new client for the given repo path.

  Options:
  - `:bd_path` — path to the `bd` binary (default: BEADS_BD_PATH env or "bd")
  """
  @spec new(String.t(), keyword()) :: t()
  def new(repo_path, opts \\ []) do
    bd_path =
      Keyword.get(opts, :bd_path) ||
        System.get_env("BEADS_BD_PATH") ||
        Application.get_env(:keiro, :beads_bd_path, "bd")

    %__MODULE__{repo_path: repo_path, bd_path: bd_path}
  end

  @doc "Check that bd is installed and reachable."
  @spec check_installed(t()) :: {:ok, String.t()} | {:error, String.t()}
  def check_installed(%__MODULE__{} = client) do
    run_bd(client, ["--version"])
  end

  @doc """
  Create a new bead.

  Options: `:id`, `:type`, `:priority`, `:labels`, `:description`
  """
  @spec create(t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def create(%__MODULE__{} = client, title, opts \\ []) do
    args =
      ["create", title, "--silent"] ++
        opt_args(opts, :id, "--id") ++
        opt_args(opts, :type, "--type") ++
        opt_args(opts, :priority, "--priority") ++
        opt_args(opts, :description, "--description") ++
        label_args(opts)

    run_bd(client, args)
  end

  @doc "Update a bead's status."
  @spec update_status(t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def update_status(%__MODULE__{} = client, id, status) do
    run_bd(client, ["update", id, "--status", status])
  end

  @doc "Close a bead."
  @spec close(t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def close(%__MODULE__{} = client, id) do
    run_bd(client, ["close", id])
  end

  @doc """
  List beads as parsed structs.

  Options: `:status`, `:limit` (default: 0 for all)
  """
  @spec list(t(), keyword()) :: {:ok, [Bead.t()]} | {:error, String.t()}
  def list(%__MODULE__{} = client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 0)

    args =
      ["list", "--json", "--limit", to_string(limit)] ++
        opt_args(opts, :status, "--status")

    case run_bd(client, args) do
      {:ok, stdout} -> parse_beads_json(stdout)
      error -> error
    end
  end

  @doc "List ready (unblocked) beads sorted by priority."
  @spec ready(t()) :: {:ok, [Bead.t()]} | {:error, String.t()}
  def ready(%__MODULE__{} = client) do
    case run_bd(client, ["ready", "--json"]) do
      {:ok, stdout} -> parse_beads_json(stdout)
      error -> error
    end
  end

  @doc "Link two beads (from depends on to)."
  @spec link(t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def link(%__MODULE__{} = client, from, to) do
    run_bd(client, ["link", from, to])
  end

  @doc "Run a raw bd command and return stdout or stderr."
  @spec run_bd(t(), [String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def run_bd(%__MODULE__{bd_path: bd_path, repo_path: repo_path}, args) do
    case System.cmd(bd_path, args, cd: repo_path, stderr_to_stdout: false) do
      {stdout, 0} -> {:ok, String.trim(stdout)}
      {stdout, _code} -> {:error, String.trim(stdout)}
    end
  rescue
    e in ErlangError ->
      {:error, "bd not found: #{inspect(e)}"}
  end

  # -- private helpers --

  defp parse_beads_json(stdout) do
    case Jason.decode(stdout) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.map(items, &Bead.from_map/1)}

      {:ok, _other} ->
        {:error, "unexpected JSON shape: expected array"}

      {:error, reason} ->
        {:error, "JSON parse error: #{inspect(reason)}"}
    end
  end

  defp opt_args(opts, key, flag) do
    case Keyword.get(opts, key) do
      nil -> []
      val -> [flag, to_string(val)]
    end
  end

  defp label_args(opts) do
    opts
    |> Keyword.get_values(:label)
    |> then(fn
      [] -> Keyword.get(opts, :labels, [])
      vals -> vals
    end)
    |> Enum.flat_map(fn label -> ["--label", label] end)
  end
end
