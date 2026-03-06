defmodule Keiro.Arch.Actions.GhListIssuesTest do
  use ExUnit.Case, async: false

  alias Keiro.Arch.Actions.GhListIssues

  @mock_gh Path.expand("../../../support/mock_gh.sh", __DIR__)

  setup do
    System.put_env("GH_BIN_PATH", @mock_gh)
    on_exit(fn -> System.delete_env("GH_BIN_PATH") end)
    :ok
  end

  describe "run/2" do
    test "lists issues with parsed JSON" do
      assert {:ok, result} = GhListIssues.run(%{repo_path: "/tmp"}, %{})
      assert is_list(result.issues)
      assert result.count == length(result.issues)
      assert result.count > 0
    end

    test "issues contain author and label data" do
      assert {:ok, result} = GhListIssues.run(%{repo_path: "/tmp"}, %{})
      issue = List.first(result.issues)
      assert Map.has_key?(issue, "number")
      assert Map.has_key?(issue, "title")
      assert Map.has_key?(issue, "author")
      assert Map.has_key?(issue, "labels")
    end

    test "uses default state and limit" do
      # Should not crash with no optional params
      assert {:ok, _result} = GhListIssues.run(%{repo_path: "/tmp"}, %{})
    end

    test "accepts optional label filter" do
      assert {:ok, _result} =
               GhListIssues.run(%{repo_path: "/tmp", label: "bug"}, %{})
    end

    test "returns error when gh CLI not found" do
      System.put_env("GH_BIN_PATH", "/nonexistent/gh")
      assert {:error, _reason} = GhListIssues.run(%{repo_path: "/tmp"}, %{})
    end
  end
end
