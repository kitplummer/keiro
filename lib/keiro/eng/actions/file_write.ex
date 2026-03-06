defmodule Keiro.Eng.Actions.FileWrite do
  @moduledoc "Jido Action: write file contents (approval required)."

  use Jido.Action,
    name: "file_write",
    description: "Write content to a file in the repository",
    category: "Eng",
    tags: ["eng", "file", "write"],
    vsn: "1.0.0",
    schema: [
      path: [type: :string, required: true, doc: "File path (relative to repo_path or absolute)"],
      content: [type: :string, required: true, doc: "File content to write"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    full_path = resolve_path(params.path, params.repo_path)

    with {:ok, :approved} <-
           Approval.require(
             "Write file: #{full_path} (#{byte_size(params.content)} bytes)",
             context
           ) do
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, params.content)
      {:ok, %{written: true, path: full_path, bytes: byte_size(params.content)}}
    end
  end

  defp resolve_path("/" <> _ = absolute, _repo_path), do: absolute
  defp resolve_path(relative, repo_path), do: Path.join(repo_path, relative)
end
