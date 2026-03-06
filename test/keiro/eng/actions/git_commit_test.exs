defmodule Keiro.Eng.Actions.GitCommitTest do
  use ExUnit.Case, async: false

  alias Keiro.Eng.Actions.GitCommit

  @mock_git Path.expand("../../../support/mock_git.sh", __DIR__)

  setup do
    System.put_env("GIT_BIN_PATH", @mock_git)
    on_exit(fn -> System.delete_env("GIT_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "stages and commits files", %{approve: ctx} do
      assert {:ok, result} =
               GitCommit.run(
                 %{
                   message: "feat: add greeting",
                   paths: ["lib/greeting.ex", "test/greeting_test.exs"],
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert result.committed == true
      assert result.message == "feat: add greeting"
      assert result.output =~ "file changed"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} =
               GitCommit.run(
                 %{message: "nope", paths: ["file.txt"], repo_path: "/tmp"},
                 reject
               )

      assert msg =~ "Rejected by governance gate"
    end
  end
end
