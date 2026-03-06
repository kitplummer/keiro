defmodule Keiro.Eng.Actions.GitPush do
  @moduledoc "Jido Action: push branch to remote (approval required)."

  use Jido.Action,
    name: "git_push",
    description: "Push a git branch to the remote repository",
    category: "Eng",
    tags: ["eng", "git", "push"],
    vsn: "1.0.0",
    schema: [
      branch: [type: :string, required: true, doc: "Branch name to push"],
      remote: [type: :string, default: "origin", doc: "Remote name"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Eng.GitCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    branch = params.branch
    remote = Map.get(params, :remote, "origin")
    repo_path = params.repo_path

    with {:ok, :approved} <-
           Approval.require("Push #{branch} to #{remote}", context) do
      git = GitCli.git_path()

      case GitCli.run(git, ["push", "-u", remote, branch], cd: repo_path) do
        {:ok, output} ->
          {:ok, %{pushed: true, branch: branch, remote: remote, output: output}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
