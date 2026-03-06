defmodule Keiro.Ops.Actions.FlyLogsTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlyLogs

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    :ok
  end

  test "returns recent logs" do
    assert {:ok, result} = FlyLogs.run(%{app: "lowendinsight", lines: 50}, %{})
    assert result.logs =~ "Health check passed"
    assert result.line_count == 3
  end

  test "trims to requested line count" do
    assert {:ok, result} = FlyLogs.run(%{app: "lowendinsight", lines: 1}, %{})
    assert result.line_count == 1
    assert result.logs =~ "Health check"
  end
end
