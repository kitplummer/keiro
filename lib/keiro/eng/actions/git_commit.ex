defmodule Keiro.Eng.Actions.GitCommit do
  @moduledoc "Jido Action: stage files and commit (approval required)."

  use Jido.Action,
    name: "git_commit",
    description: "Stage specified files and create a git commit",
    category: "Eng",
    tags: ["eng", "git", "commit"],
    vsn: "1.0.0",
    schema: [
      message: [type: :string, required: true, doc: "Commit message"],
      paths: [type: {:list, :string}, required: true, doc: "Files to stage"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Eng.GitCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    message = params.message
    paths = params.paths
    repo_path = params.repo_path

    with {:ok, :approved} <-
           Approval.require("Commit #{length(paths)} file(s): #{message}", context) do
      git = GitCli.git_path()
      opts = [cd: repo_path]

      with {:ok, _} <- GitCli.run(git, ["add" | paths], opts),
           {:ok, output} <- GitCli.run(git, ["commit", "-m", message], opts) do
        {:ok, %{committed: true, message: message, output: output}}
      end
    end
  end
end
