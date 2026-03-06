defmodule Keiro.Eng.Actions.GitBranchTest do
  use ExUnit.Case, async: false

  alias Keiro.Eng.Actions.GitBranch

  @mock_git Path.expand("../../../support/mock_git.sh", __DIR__)

  setup do
    System.put_env("GIT_BIN_PATH", @mock_git)
    on_exit(fn -> System.delete_env("GIT_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "creates a new branch from base", %{approve: ctx} do
      assert {:ok, result} =
               GitBranch.run(
                 %{branch: "eng/gl-001-feature", base: "main", repo_path: "/tmp"},
                 ctx
               )

      assert result.branch == "eng/gl-001-feature"
      assert result.base == "main"
      assert result.output =~ "Switched to a new branch"
    end

    test "uses main as default base", %{approve: ctx} do
      assert {:ok, result} =
               GitBranch.run(%{branch: "eng/test", repo_path: "/tmp"}, ctx)

      assert result.base == "main"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} =
               GitBranch.run(%{branch: "eng/test", repo_path: "/tmp"}, reject)

      assert msg =~ "Rejected by governance gate"
    end
  end
end
