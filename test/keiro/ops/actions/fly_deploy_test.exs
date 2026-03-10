defmodule Keiro.Ops.Actions.FlyDeployTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlyDeploy

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  test "deploys successfully", %{approve: ctx} do
    assert {:ok, result} = FlyDeploy.run(%{app: "lowendinsight", repo_path: "/tmp"}, ctx)
    assert result.success == true
    assert result.output =~ "Deploying"
  end

  test "reports failure gracefully", %{approve: ctx} do
    System.put_env("FLY_BIN_PATH", "/nonexistent/fly")

    assert {:ok, result} = FlyDeploy.run(%{app: "lowendinsight", repo_path: "/tmp"}, ctx)
    assert result.success == false
    assert is_binary(result.error)
  end

  test "deploys with dockerfile option", %{approve: ctx} do
    assert {:ok, result} =
             FlyDeploy.run(
               %{app: "lowendinsight", repo_path: "/tmp", dockerfile: "apps/lei/Dockerfile"},
               ctx
             )

    assert result.success == true
    assert result.output =~ "Deploying"
  end

  test "rejects when governance gate rejects" do
    reject = %{approve_fn: fn _desc -> :rejected end}

    assert {:error, msg} = FlyDeploy.run(%{app: "lowendinsight", repo_path: "/tmp"}, reject)
    assert msg =~ "Rejected by governance gate"
  end
end
