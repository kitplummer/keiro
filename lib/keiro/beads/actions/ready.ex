defmodule Keiro.Beads.Actions.Ready do
  @moduledoc "Jido Action: list ready (unblocked) beads sorted by priority."

  use Jido.Action,
    name: "beads_ready",
    description: "List ready (unblocked) beads from the task graph, sorted by priority",
    category: "Beads",
    tags: ["beads", "task", "ready"],
    vsn: "1.0.0",
    schema: [
      repo_path: [type: :string, required: true, doc: "Path to the beads-enabled repo"]
    ]

  alias Keiro.Beads.Client

  @impl Jido.Action
  def run(params, _context) do
    client = Client.new(params.repo_path)

    case Client.ready(client) do
      {:ok, beads} ->
        {:ok, %{beads: beads, count: length(beads)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
