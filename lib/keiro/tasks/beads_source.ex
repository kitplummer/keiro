defmodule Keiro.Tasks.BeadsSource do
  @moduledoc """
  Task source backed by the beads CLI (`bd`).

  Wraps `Keiro.Beads.Client` and converts beads to generic `Task` structs.
  """

  @behaviour Keiro.Tasks.Source

  alias Keiro.Beads.Client, as: BeadsClient
  alias Keiro.Tasks.Task

  @impl true
  def ready(opts) do
    client = client_from_opts(opts)

    case BeadsClient.ready(client) do
      {:ok, beads} -> {:ok, Enum.map(beads, &Task.from_bead/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list(opts) do
    client = client_from_opts(opts)
    list_opts = Keyword.take(opts, [:status, :limit])

    case BeadsClient.list(client, list_opts) do
      {:ok, beads} -> {:ok, Enum.map(beads, &Task.from_bead/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_status(task_id, status, opts) do
    client = client_from_opts(opts)

    case BeadsClient.update_status(client, task_id, status) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def close(task_id, opts) do
    client = client_from_opts(opts)

    case BeadsClient.close(client, task_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp client_from_opts(opts) do
    repo_path = Keyword.fetch!(opts, :repo_path)
    BeadsClient.new(repo_path)
  end
end
