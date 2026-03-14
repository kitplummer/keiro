defmodule Keiro.Arch.Actions.GhCreateIssue do
  @moduledoc "Jido Action: create a GitHub issue via gh CLI (approval required)."

  use Jido.Action,
    name: "gh_create_issue",
    description: "Create a GitHub issue using the gh CLI",
    category: "Arch",
    tags: ["arch", "github", "issue"],
    vsn: "1.0.0",
    schema: [
      title: [type: :string, required: true, doc: "Issue title"],
      body: [type: :string, required: true, doc: "Issue body (markdown)"],
      labels: [type: {:list, :string}, default: [], doc: "Labels to attach"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Eng.GhCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    title = params.title
    repo_path = params.repo_path
    labels = Map.get(params, :labels, [])

    with {:ok, :approved} <-
           Approval.require("Create issue: #{title}", context) do
      gh = GhCli.gh_path()

      args =
        ["issue", "create", "--title", title, "--body", params.body] ++
          Enum.flat_map(labels, fn label -> ["--label", label] end)

      case GhCli.run(gh, args, cd: repo_path) do
        {:ok, output} ->
          {:ok, %{issue_url: String.trim(output), title: title}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
