defmodule Keiro.Ops.Actions.FlyDeploy do
  @moduledoc "Jido Action: deploy a fly.io app from a repo path."

  use Jido.Action,
    name: "fly_deploy",
    description: "Deploy a fly.io application from a local repository",
    category: "Ops",
    tags: ["fly", "deploy", "ops"],
    vsn: "1.0.0",
    schema: [
      app: [type: :string, required: true, doc: "Fly.io app name"],
      repo_path: [type: :string, required: true, doc: "Path to the repo to deploy from"],
      no_cache: [type: :boolean, default: false, doc: "Disable Docker build cache"]
    ]

  alias Keiro.Ops.FlyCli

  @impl Jido.Action
  def run(params, _context) do
    fly = FlyCli.fly_path()

    args =
      ["deploy", "--app", params.app] ++
        if(Map.get(params, :no_cache, false), do: ["--no-cache"], else: [])

    case FlyCli.run(fly, args, cd: params.repo_path) do
      {:ok, output} ->
        {:ok, %{success: true, output: output}}

      {:error, reason} ->
        {:ok, %{success: false, error: reason}}
    end
  end
end
