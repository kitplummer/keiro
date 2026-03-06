defmodule Keiro.Ops.Actions.FlySSHTest do
  use ExUnit.Case, async: false

  alias Keiro.Ops.Actions.FlySSH

  @mock_fly Path.expand("../../../support/mock_fly.sh", __DIR__)

  setup do
    System.put_env("FLY_BIN_PATH", @mock_fly)
    on_exit(fn -> System.delete_env("FLY_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  test "executes command and returns output", %{approve: ctx} do
    assert {:ok, %{output: output}} = FlySSH.run(%{app: "lowendinsight", command: "ls /"}, ctx)
    assert output =~ "command output from container"
  end

  test "rejects when governance gate rejects" do
    reject = %{approve_fn: fn _desc -> :rejected end}

    assert {:error, msg} = FlySSH.run(%{app: "lowendinsight", command: "ls /"}, reject)
    assert msg =~ "Rejected by governance gate"
  end
end
