defmodule Keiro.Eng.Actions.GitBranch do
  @moduledoc "Jido Action: create a new git branch (approval required)."

  use Jido.Action,
    name: "git_branch",
    description: "Create a new git branch from a base branch",
    category: "Eng",
    tags: ["eng", "git", "branch"],
    vsn: "1.0.0",
    schema: [
      branch: [type: :string, required: true, doc: "New branch name"],
      base: [type: :string, default: "main", doc: "Base branch to create from"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Eng.GitCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    branch = params.branch
    base = Map.get(params, :base, "main")
    repo_path = params.repo_path

    with {:ok, :approved} <-
           Approval.require("Create branch #{branch} from #{base}", context) do
      git = GitCli.git_path()
      opts = [cd: repo_path]

      with {:ok, _} <- GitCli.run(git, ["checkout", base], opts),
           {:ok, _} <- GitCli.run(git, ["pull", "--rebase"], opts),
           {:ok, output} <- GitCli.run(git, ["checkout", "-b", branch], opts) do
        {:ok, %{branch: branch, base: base, output: output}}
      end
    end
  end
end
