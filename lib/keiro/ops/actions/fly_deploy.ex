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
      no_cache: [type: :boolean, default: false, doc: "Disable Docker build cache"],
      dockerfile: [type: :string, doc: "Path to Dockerfile (relative to repo_path)"]
    ]

  alias Keiro.Ops.FlyCli
  alias Keiro.Governance.Approval

  @impl Jido.Action
  def run(params, context) do
    repo_path = resolve_repo_path(params.repo_path, context)

    with {:ok, :approved} <-
           Approval.require("Deploy #{params.app} from #{repo_path}", context) do
      fly = FlyCli.fly_path()

      args =
        ["deploy", "--app", params.app] ++
          if(Map.get(params, :no_cache, false), do: ["--no-cache"], else: []) ++
          if(Map.get(params, :dockerfile), do: ["--dockerfile", params.dockerfile], else: [])

      case FlyCli.run(fly, args, cd: repo_path) do
        {:ok, output} ->
          {:ok, %{success: true, output: output}}

        {:error, reason} ->
          {:ok, %{success: false, error: reason}}
      end
    end
  end

  defp resolve_repo_path(".", context), do: Map.get(context, :repo_path, ".")
  defp resolve_repo_path("/" <> _ = path, _context), do: path
  defp resolve_repo_path(_relative, context), do: Map.get(context, :repo_path, ".")
end
