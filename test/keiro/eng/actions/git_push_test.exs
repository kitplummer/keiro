defmodule Keiro.Eng.Actions.GitPushTest do
  use ExUnit.Case, async: false

  alias Keiro.Eng.Actions.GitPush

  @mock_git Path.expand("../../../support/mock_git.sh", __DIR__)

  setup do
    System.put_env("GIT_BIN_PATH", @mock_git)
    on_exit(fn -> System.delete_env("GIT_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "pushes branch to remote", %{approve: ctx} do
      assert {:ok, result} =
               GitPush.run(
                 %{branch: "eng/gl-001-feature", remote: "origin", repo_path: "/tmp"},
                 ctx
               )

      assert result.pushed == true
      assert result.branch == "eng/gl-001-feature"
      assert result.remote == "origin"
    end

    test "defaults to origin remote", %{approve: ctx} do
      assert {:ok, result} =
               GitPush.run(%{branch: "eng/test", repo_path: "/tmp"}, ctx)

      assert result.remote == "origin"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} =
               GitPush.run(%{branch: "eng/test", repo_path: "/tmp"}, reject)

      assert msg =~ "Rejected by governance gate"
    end
  end
end
