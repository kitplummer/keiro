defmodule Keiro.Eng.Actions.GhCreatePrTest do
  use ExUnit.Case, async: false

  alias Keiro.Eng.Actions.GhCreatePr

  @mock_gh Path.expand("../../../support/mock_gh.sh", __DIR__)

  setup do
    System.put_env("GH_BIN_PATH", @mock_gh)
    on_exit(fn -> System.delete_env("GH_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "creates a pull request", %{approve: ctx} do
      assert {:ok, result} =
               GhCreatePr.run(
                 %{
                   title: "feat: add greeting",
                   body: "Adds greeting function",
                   base: "main",
                   head: "eng/gl-001-feature",
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert result.pr_url =~ "github.com/test/repo/pull/42"
      assert result.title == "feat: add greeting"
      assert result.base == "main"
      assert result.head == "eng/gl-001-feature"
    end

    test "defaults to main base branch", %{approve: ctx} do
      assert {:ok, result} =
               GhCreatePr.run(
                 %{
                   title: "fix: something",
                   body: "Fix",
                   head: "eng/test",
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert result.base == "main"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} =
               GhCreatePr.run(
                 %{
                   title: "nope",
                   body: "nope",
                   head: "eng/test",
                   repo_path: "/tmp"
                 },
                 reject
               )

      assert msg =~ "Rejected by governance gate"
    end
  end
end
