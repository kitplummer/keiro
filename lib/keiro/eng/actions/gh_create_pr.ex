defmodule Keiro.Eng.Actions.GhCreatePr do
  @moduledoc "Jido Action: create a GitHub pull request via gh CLI (approval required)."

  use Jido.Action,
    name: "gh_create_pr",
    description: "Create a GitHub pull request using the gh CLI",
    category: "Eng",
    tags: ["eng", "github", "pr"],
    vsn: "1.0.0",
    schema: [
      title: [type: :string, required: true, doc: "PR title"],
      body: [type: :string, required: true, doc: "PR body/description"],
      base: [type: :string, default: "main", doc: "Base branch"],
      head: [type: :string, required: true, doc: "Head branch"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Eng.GhCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    title = params.title
    base = Map.get(params, :base, "main")
    head = params.head
    repo_path = params.repo_path

    with {:ok, :approved} <-
           Approval.require("Create PR: #{title} (#{head} → #{base})", context) do
      gh = GhCli.gh_path()

      args = [
        "pr",
        "create",
        "--title",
        title,
        "--body",
        params.body,
        "--base",
        base,
        "--head",
        head
      ]

      case GhCli.run(gh, args, cd: repo_path) do
        {:ok, output} ->
          {:ok, %{pr_url: String.trim(output), title: title, base: base, head: head}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
