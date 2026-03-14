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

    # Scan both flat docs/ and docs/adr/ subdirectory
    flat = Path.join(docs_path, pattern) |> Path.wildcard()
    nested = Path.join([docs_path, "adr", pattern]) |> Path.wildcard()

    # Also match ADR-*.md (uppercase) in both locations
    upper_pattern = String.replace(pattern, "adr-", "ADR-")

    {flat_upper, nested_upper} =
      if upper_pattern != pattern do
        {
          Path.join(docs_path, upper_pattern) |> Path.wildcard(),
          Path.join([docs_path, "adr", upper_pattern]) |> Path.wildcard()
        }
      else
        {[], []}
      end

    files =
      (flat ++ nested ++ flat_upper ++ nested_upper)
      |> Enum.uniq()
      |> Enum.sort()

    {:ok, %{files: files, count: length(files)}}
  end
end
