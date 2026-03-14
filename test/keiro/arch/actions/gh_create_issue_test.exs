defmodule Keiro.Arch.Actions.GhCreateIssueTest do
  use ExUnit.Case, async: false

  alias Keiro.Arch.Actions.GhCreateIssue

  @mock_gh Path.expand("../../../support/mock_gh.sh", __DIR__)

  setup do
    System.put_env("GH_BIN_PATH", @mock_gh)
    on_exit(fn -> System.delete_env("GH_BIN_PATH") end)
    {:ok, approve: %{approve_fn: fn _desc -> :approved end}}
  end

  describe "run/2" do
    test "creates a GitHub issue", %{approve: ctx} do
      assert {:ok, result} =
               GhCreateIssue.run(
                 %{
                   title: "ADR-001 WI-1: Rename agentic_risk",
                   body: "Rename agentic_risk to agentic_classification",
                   labels: ["eng", "arch"],
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert result.issue_url =~ "github.com/test/repo/issues/99"
      assert result.title == "ADR-001 WI-1: Rename agentic_risk"
    end

    test "creates issue without labels", %{approve: ctx} do
      assert {:ok, result} =
               GhCreateIssue.run(
                 %{
                   title: "Simple issue",
                   body: "Description here",
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert result.issue_url =~ "github.com/test/repo/issues/99"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} =
               GhCreateIssue.run(
                 %{
                   title: "nope",
                   body: "nope",
                   repo_path: "/tmp"
                 },
                 reject
               )

      assert msg =~ "Rejected by governance gate"
    end

    test "returns error when gh CLI not found" do
      System.put_env("GH_BIN_PATH", "/nonexistent/gh")
      ctx = %{approve_fn: fn _desc -> :approved end}

      assert {:error, msg} =
               GhCreateIssue.run(
                 %{
                   title: "test",
                   body: "test",
                   repo_path: "/tmp"
                 },
                 ctx
               )

      assert msg =~ "not found"
    end
  end
end
