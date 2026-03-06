defmodule Keiro.Arch.Actions.GhListIssues do
  @moduledoc "Jido Action: list GitHub issues via gh CLI."

  use Jido.Action,
    name: "gh_list_issues",
    description: "List GitHub issues using the gh CLI",
    category: "Arch",
    tags: ["arch", "github", "issues"],
    vsn: "1.0.0",
    schema: [
      repo_path: [type: :string, required: true, doc: "Repository root path"],
      state: [type: :string, default: "open", doc: "Issue state filter: open, closed, all"],
      limit: [type: :integer, default: 30, doc: "Maximum number of issues to return"],
      label: [type: :string, doc: "Filter by label"]
    ]

  alias Keiro.Eng.GhCli

  @impl Jido.Action
  def run(params, _context) do
    repo_path = params.repo_path
    state = Map.get(params, :state, "open")
    limit = Map.get(params, :limit, 30)
    label = Map.get(params, :label)
    gh = GhCli.gh_path()

    args =
      [
        "issue",
        "list",
        "--json",
        "number,title,body,state,labels,createdAt,author",
        "--state",
        state,
        "--limit",
        to_string(limit)
      ]
      |> maybe_add_label(label)

    case GhCli.run(gh, args, cd: repo_path) do
      {:ok, output} ->
        issues = Jason.decode!(output)
        {:ok, %{issues: issues, count: length(issues)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_label(args, nil), do: args
  defp maybe_add_label(args, label), do: args ++ ["--label", label]
end
