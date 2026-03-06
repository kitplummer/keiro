defmodule Keiro.Ops.Actions.FlyStatusTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlyStatus

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    # Override fly path for tests
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    :ok
  end

  test "returns parsed status" do
    assert {:ok, result} = FlyStatus.run(%{app: "lowendinsight"}, %{})
    assert result.state == "running"
    assert is_map(result.raw)
  end
end
