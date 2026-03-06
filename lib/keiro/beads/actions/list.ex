defmodule Keiro.Beads.Actions.List do
  @moduledoc "Jido Action: list beads from the task graph."

  use Jido.Action,
    name: "beads_list",
    description: "List beads (tasks) from the Beads task graph",
    category: "Beads",
    tags: ["beads", "task", "list"],
    vsn: "1.0.0",
    schema: [
      status: [type: :string, doc: "Filter by status"],
      limit: [type: :integer, default: 0, doc: "Max results (0 = all)"],
      repo_path: [type: :string, required: true, doc: "Path to the beads-enabled repo"]
    ]

  alias Keiro.Beads.Client

  @impl Jido.Action
  def run(params, _context) do
    client = Client.new(params.repo_path)

    opts =
      [limit: Map.get(params, :limit, 0)]
      |> maybe_put(:status, Map.get(params, :status))

    case Client.list(client, opts) do
      {:ok, beads} ->
        {:ok, %{beads: beads, count: length(beads)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, val), do: Keyword.put(opts, key, val)
end
