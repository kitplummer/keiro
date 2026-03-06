defmodule Keiro.TaskSource.Beads do
  @moduledoc """
  TaskSource implementation backed by the Beads task graph (`bd` CLI).

  Wraps `Keiro.Beads.Client` to conform to the `Keiro.TaskSource`
  behaviour, providing the default task source for the orchestrator.

  ## Usage

      source = Keiro.TaskSource.Beads.new("/path/to/repo")
      {:ok, tasks} = Keiro.TaskSource.list(source)
      {:ok, ready} = Keiro.TaskSource.ready(source)
  """

  @behaviour Keiro.TaskSource

  alias Keiro.Beads.Client

  @type t :: %__MODULE__{client: Client.t()}

  defstruct [:client]

  @doc "Create a Beads task source for the given repo path."
  @spec new(String.t(), keyword()) :: t()
  def new(repo_path, opts \\ []) do
    %__MODULE__{client: Client.new(repo_path, opts)}
  end

  @impl Keiro.TaskSource
  def list(%__MODULE__{client: client}, opts \\ []) do
    Client.list(client, opts)
  end

  @impl Keiro.TaskSource
  def ready(%__MODULE__{client: client}) do
    Client.ready(client)
  end

  @impl Keiro.TaskSource
  def update_status(%__MODULE__{client: client}, id, status) do
    Client.update_status(client, id, status)
  end

  @impl Keiro.TaskSource
  def close(%__MODULE__{client: client}, id) do
    Client.close(client, id)
  end
end
