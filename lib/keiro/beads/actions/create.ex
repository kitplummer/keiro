defmodule Keiro.Beads.Actions.Create do
  @moduledoc "Jido Action: create a bead in the task graph."

  use Jido.Action,
    name: "beads_create",
    description: "Create a new bead (task) in the Beads task graph",
    category: "Beads",
    tags: ["beads", "task", "create"],
    vsn: "1.0.0",
    schema: [
      title: [type: :string, required: true, doc: "Bead title (max 200 chars)"],
      id: [type: :string, doc: "Custom bead ID"],
      type: [type: :string, default: "task", doc: "Issue type: task, bug, feature, etc."],
      priority: [type: :integer, default: 2, doc: "Priority 0-4 (P0=critical, P4=backlog)"],
      labels: [type: {:list, :string}, default: [], doc: "Labels to attach"],
      description: [type: :string, doc: "Detailed description"],
      repo_path: [type: :string, required: true, doc: "Path to the beads-enabled repo"]
    ]

  alias Keiro.Beads.Client

  @impl Jido.Action
  def run(params, _context) do
    client = Client.new(params.repo_path)

    opts =
      []
      |> maybe_put(:id, Map.get(params, :id))
      |> maybe_put(:type, Map.get(params, :type))
      |> maybe_put(:priority, Map.get(params, :priority))
      |> maybe_put(:description, Map.get(params, :description))
      |> put_labels(Map.get(params, :labels, []))

    case Client.create(client, params.title, opts) do
      {:ok, output} -> {:ok, %{created: true, output: output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)

  defp put_labels(opts, []), do: opts
  defp put_labels(opts, labels), do: Keyword.put(opts, :labels, labels)
end
