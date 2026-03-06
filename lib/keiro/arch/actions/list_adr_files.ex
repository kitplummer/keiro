defmodule Keiro.Arch.Actions.ListAdrFiles do
  @moduledoc "Jido Action: list ADR files in a repository."

  use Jido.Action,
    name: "list_adr_files",
    description: "List Architecture Decision Record files in the repository",
    category: "Arch",
    tags: ["arch", "adr", "docs"],
    vsn: "1.0.0",
    schema: [
      repo_path: [type: :string, required: true, doc: "Repository root path"],
      pattern: [type: :string, default: "adr-*.md", doc: "Glob pattern for ADR files"]
    ]

  @impl Jido.Action
  def run(params, _context) do
    repo_path = params.repo_path
    pattern = Map.get(params, :pattern, "adr-*.md")
    docs_path = Path.join(repo_path, "docs")
    glob = Path.join(docs_path, pattern)

    files =
      glob
      |> Path.wildcard()
      |> Enum.sort()

    {:ok, %{files: files, count: length(files)}}
  end
end
