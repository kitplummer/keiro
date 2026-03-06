defmodule Keiro.Beads.Bead do
  @moduledoc """
  Struct mirroring `bd list --json` output.

  Implements `Keiro.Task` behaviour for use with the generic
  TaskSource abstraction.

  Statuses: "open" | "in_progress" | "blocked" | "closed" | "deferred"
  Priority: 0-4 (P0=critical through P4=backlog), default 2
  """

  use Keiro.Task

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          status: String.t() | nil,
          priority: non_neg_integer() | nil,
          issue_type: String.t() | nil,
          dependencies: [map()] | nil,
          external_ref: String.t() | nil,
          labels: [String.t()] | nil,
          assignee: String.t() | nil,
          created_at: String.t() | nil
        }

  defstruct [
    :id,
    :title,
    :description,
    :status,
    :priority,
    :issue_type,
    :dependencies,
    :external_ref,
    :labels,
    :assignee,
    :created_at
  ]

  @doc """
  Parse a map (from JSON) into a Bead struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      title: map["title"],
      description: map["description"],
      status: map["status"],
      priority: map["priority"],
      issue_type: map["issue_type"] || map["type"],
      dependencies: map["dependencies"] || [],
      external_ref: map["external_ref"],
      labels: map["labels"] || [],
      assignee: map["assignee"],
      created_at: map["created_at"]
    }
  end

  # -- Keiro.Task callbacks --

  @impl Keiro.Task
  def id(%__MODULE__{id: id}), do: id

  @impl Keiro.Task
  def title(%__MODULE__{title: title}), do: title

  @impl Keiro.Task
  def description(%__MODULE__{description: desc}), do: desc

  @impl Keiro.Task
  def status(%__MODULE__{status: status}), do: status

  @impl Keiro.Task
  def priority(%__MODULE__{priority: priority}), do: priority

  @impl Keiro.Task
  def labels(%__MODULE__{labels: labels}), do: labels || []
end
