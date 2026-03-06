defmodule Keiro.Ops.Actions.FlyDeployTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlyDeploy

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    :ok
  end

  test "deploys successfully" do
    assert {:ok, result} = FlyDeploy.run(%{app: "lowendinsight", repo_path: "/tmp"}, %{})
    assert result.success == true
    assert result.output =~ "Deploying"
  end

  test "reports failure gracefully" do
    System.put_env("FLY_BIN_PATH", "/nonexistent/fly")

    assert {:ok, result} = FlyDeploy.run(%{app: "lowendinsight", repo_path: "/tmp"}, %{})
    assert result.success == false
    assert is_binary(result.error)
  end
end
