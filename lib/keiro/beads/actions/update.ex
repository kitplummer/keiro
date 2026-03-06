defmodule Keiro.Beads.Actions.Update do
  @moduledoc "Jido Action: update a bead's status."

  use Jido.Action,
    name: "beads_update",
    description: "Update the status of a bead in the task graph",
    category: "Beads",
    tags: ["beads", "task", "update"],
    vsn: "1.0.0",
    schema: [
      id: [type: :string, required: true, doc: "Bead ID to update"],
      status: [
        type: {:in, ["open", "in_progress", "blocked", "closed", "deferred"]},
        required: true,
        doc: "New status"
      ],
      repo_path: [type: :string, required: true, doc: "Path to the beads-enabled repo"]
    ]

  alias Keiro.Beads.Client

  @impl Jido.Action
  def run(params, _context) do
    client = Client.new(params.repo_path)

    case Client.update_status(client, params.id, params.status) do
      {:ok, output} ->
        {:ok, %{updated: true, id: params.id, status: params.status, output: output}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
