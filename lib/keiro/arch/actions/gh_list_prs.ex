defmodule Keiro.Arch.Actions.GhListPrs do
  @moduledoc "Jido Action: list GitHub pull requests via gh CLI."

  use Jido.Action,
    name: "gh_list_prs",
    description: "List GitHub pull requests using the gh CLI",
    category: "Arch",
    tags: ["arch", "github", "pr"],
    vsn: "1.0.0",
    schema: [
      repo_path: [type: :string, required: true, doc: "Repository root path"],
      state: [type: :string, default: "open", doc: "PR state filter: open, closed, merged, all"],
      limit: [type: :integer, default: 20, doc: "Maximum number of PRs to return"]
    ]

  alias Keiro.Eng.GhCli

  @impl Jido.Action
  def run(params, _context) do
    repo_path = params.repo_path
    state = Map.get(params, :state, "open")
    limit = Map.get(params, :limit, 20)
    gh = GhCli.gh_path()

    args = [
      "pr",
      "list",
      "--json",
      "number,title,state,labels,author,createdAt",
      "--state",
      state,
      "--limit",
      to_string(limit)
    ]

    case GhCli.run(gh, args, cd: repo_path) do
      {:ok, output} ->
        prs = Jason.decode!(output)
        {:ok, %{prs: prs, count: length(prs)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
