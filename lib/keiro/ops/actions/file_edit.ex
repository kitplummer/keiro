defmodule Keiro.Ops.Actions.FileEdit do
  @moduledoc """
  Jido Action: SRE-scoped file editing.

  Restricts edits to infrastructure/config files only — Dockerfiles, fly.toml,
  rel/env.sh.eex, application.ex, config/runtime.exs. Rejects edits to
  application business logic.
  """

  use Jido.Action,
    name: "file_edit",
    description:
      "Edit infrastructure/config files (SRE scope only: Dockerfile, fly.toml, env.sh.eex, application.ex, runtime.exs)",
    category: "Ops",
    tags: ["ops", "file", "edit", "sre"],
    vsn: "1.0.0",
    schema: [
      path: [type: :string, required: true, doc: "File path to write"],
      content: [type: :string, required: true, doc: "New file content"]
    ]

  @allowed_patterns [
    ~r/Dockerfile/,
    ~r/fly\.toml$/,
    ~r/rel\/env\.sh\.eex$/,
    ~r/application\.ex$/,
    ~r/config\/runtime\.exs$/,
    ~r/config\/prod\.exs$/,
    ~r/\.fly\//
  ]

  @impl Jido.Action
  def run(params, _context) do
    path = params.path

    if allowed_path?(path) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, params.content)
      {:ok, %{written: true, path: path, bytes: byte_size(params.content)}}
    else
      {:error,
       "outside SRE scope: #{path} — only infra files (Dockerfile, fly.toml, env.sh.eex, application.ex, runtime.exs) may be edited"}
    end
  end

  defp allowed_path?(path) do
    Enum.any?(@allowed_patterns, &Regex.match?(&1, path))
  end
end
