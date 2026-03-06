defmodule Keiro.Ops.Actions.FlySSHTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlySSH

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    :ok
  end

  test "executes command and returns output" do
    assert {:ok, %{output: output}} = FlySSH.run(%{app: "lowendinsight", command: "ls /"}, %{})
    assert output =~ "command output from container"
  end
end
