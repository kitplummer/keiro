defmodule Keiro.Eng.Actions.FileRead do
  @moduledoc "Jido Action: read file contents."

  use Jido.Action,
    name: "file_read",
    description: "Read the contents of a file in the repository",
    category: "Eng",
    tags: ["eng", "file", "read"],
    vsn: "1.0.0",
    schema: [
      path: [type: :string, required: true, doc: "File path (relative to repo_path or absolute)"],
      repo_path: [type: :string, required: true, doc: "Repository root path"]
    ]

  @impl Jido.Action
  def run(params, _context) do
    full_path = resolve_path(params.path, params.repo_path)

    case File.read(full_path) do
      {:ok, content} ->
        {:ok, %{content: content, path: full_path, bytes: byte_size(content)}}

      {:error, reason} ->
        {:error, "Cannot read #{full_path}: #{inspect(reason)}"}
    end
  end

  defp resolve_path("/" <> _ = absolute, _repo_path), do: absolute
  defp resolve_path(relative, repo_path), do: Path.join(repo_path, relative)
end
