defmodule Keiro.Ops.Actions.FlyStatus do
  @moduledoc "Jido Action: check fly.io app status."

  use Jido.Action,
    name: "fly_status",
    description: "Get the status of a fly.io application including state and health checks",
    category: "Ops",
    tags: ["fly", "status", "ops"],
    vsn: "1.0.0",
    schema: [
      app: [type: :string, required: true, doc: "Fly.io app name"]
    ]

  alias Keiro.Ops.FlyCli

  @impl Jido.Action
  def run(params, _context) do
    fly = FlyCli.fly_path()

    case FlyCli.run(fly, ["status", "--app", params.app, "--json"]) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, data} ->
            {:ok, %{state: data["Status"] || data["state"], raw: data}}

          {:error, _} ->
            {:ok, %{state: "unknown", raw_text: output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
