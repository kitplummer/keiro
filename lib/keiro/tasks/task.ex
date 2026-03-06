defmodule Keiro.Tasks.Task do
  @moduledoc """
  Generic task struct — the unit of work for the orchestrator.

  Provider-agnostic: can be sourced from beads, GitHub issues, JIRA,
  or any backend implementing `Keiro.Tasks.Source`.

  The `payload` field carries source-specific data (e.g., full bead
  struct, GitHub issue metadata) for agents that need it.
  """

  @type status :: :open | :in_progress | :blocked | :closed | :deferred

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          status: status(),
          priority: non_neg_integer(),
          labels: [String.t()],
          dependencies: [String.t()],
          payload: map(),
          source: atom()
        }

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    description: nil,
    status: :open,
    priority: 2,
    labels: [],
    dependencies: [],
    payload: %{},
    source: :unknown
  ]

  @doc "Create from a Keiro.Beads.Bead struct."
  @spec from_bead(Keiro.Beads.Bead.t()) :: t()
  def from_bead(bead) do
    status =
      case bead.status do
        "open" -> :open
        "in_progress" -> :in_progress
        "blocked" -> :blocked
        "closed" -> :closed
        "deferred" -> :deferred
        _ -> :open
      end

    %__MODULE__{
      id: bead.id,
      title: bead.title || "",
      description: bead.description,
      status: status,
      priority: bead.priority || 2,
      labels: bead.labels || [],
      dependencies: extract_dep_ids(bead.dependencies),
      payload: %{bead: bead},
      source: :beads
    }
  end

  defp extract_dep_ids(nil), do: []

  defp extract_dep_ids(deps) when is_list(deps) do
    Enum.map(deps, fn
      %{"id" => id} -> id
      %{id: id} -> id
      id when is_binary(id) -> id
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
