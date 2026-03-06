defmodule Keiro.Ops.Actions.FlySSH do
  @moduledoc "Jido Action: run a command on a fly.io app via SSH."

  use Jido.Action,
    name: "fly_ssh",
    description: "Execute a command on a fly.io application via SSH console",
    category: "Ops",
    tags: ["fly", "ssh", "ops"],
    vsn: "1.0.0",
    schema: [
      app: [type: :string, required: true, doc: "Fly.io app name"],
      command: [type: :string, required: true, doc: "Command to execute"]
    ]

  alias Keiro.Ops.FlyCli

  @impl Jido.Action
  def run(params, _context) do
    fly = FlyCli.fly_path()

    case FlyCli.run(fly, ["ssh", "console", "--app", params.app, "-C", params.command]) do
      {:ok, output} -> {:ok, %{output: output}}
      {:error, reason} -> {:error, reason}
    end
  end
end
