defmodule Keiro.Arch.Actions.GhReadIssue do
  @moduledoc "Jido Action: read a single GitHub issue via gh CLI."

  use Jido.Action,
    name: "gh_read_issue",
    description: "Read a single GitHub issue with comments using the gh CLI",
    category: "Arch",
    tags: ["arch", "github", "issue"],
    vsn: "1.0.0",
    schema: [
      repo_path: [type: :string, required: true, doc: "Repository root path"],
      number: [type: :integer, required: true, doc: "Issue number"]
    ]

  alias Keiro.Eng.GhCli

  @impl Jido.Action
  def run(params, _context) do
    repo_path = params.repo_path
    number = params.number
    gh = GhCli.gh_path()

    args = [
      "issue",
      "view",
      to_string(number),
      "--json",
      "number,title,body,state,labels,comments,author,createdAt"
    ]

    case GhCli.run(gh, args, cd: repo_path) do
      {:ok, output} ->
        issue = Jason.decode!(output)
        {:ok, %{issue: issue}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
