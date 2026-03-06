defmodule Keiro.Ops.Actions.FlyLogs do
  @moduledoc "Jido Action: fetch recent logs from a fly.io app."

  use Jido.Action,
    name: "fly_logs",
    description: "Fetch recent logs from a fly.io application",
    category: "Ops",
    tags: ["fly", "logs", "ops"],
    vsn: "1.0.0",
    schema: [
      app: [type: :string, required: true, doc: "Fly.io app name"],
      lines: [type: :integer, default: 50, doc: "Number of recent log lines"]
    ]

  alias Keiro.Ops.FlyCli

  @impl Jido.Action
  def run(params, _context) do
    fly = FlyCli.fly_path()
    lines = Map.get(params, :lines, 50)

    case FlyCli.run(fly, ["logs", "--app", params.app, "--no-tail"]) do
      {:ok, output} ->
        trimmed =
          output
          |> String.split("\n")
          |> Enum.take(-lines)
          |> Enum.join("\n")

        {:ok, %{logs: trimmed, line_count: length(String.split(trimmed, "\n"))}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
