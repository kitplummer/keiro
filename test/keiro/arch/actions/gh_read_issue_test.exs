defmodule Keiro.Arch.Actions.GhReadIssueTest do
  use ExUnit.Case, async: false

  alias Keiro.Arch.Actions.GhReadIssue

  @mock_gh Path.expand("../../../support/mock_gh.sh", __DIR__)

  setup do
    System.put_env("GH_BIN_PATH", @mock_gh)
    on_exit(fn -> System.delete_env("GH_BIN_PATH") end)
    :ok
  end

  describe "run/2" do
    test "reads a single issue with comments" do
      assert {:ok, result} = GhReadIssue.run(%{repo_path: "/tmp", number: 1}, %{})
      assert is_map(result.issue)
      assert result.issue["number"] == 1
      assert result.issue["title"] == "Add authentication"
      assert is_list(result.issue["comments"])
      assert length(result.issue["comments"]) > 0
    end

    test "issue contains author data" do
      assert {:ok, result} = GhReadIssue.run(%{repo_path: "/tmp", number: 1}, %{})
      assert result.issue["author"]["login"] == "legit-user"
    end

    test "returns error when gh CLI not found" do
      System.put_env("GH_BIN_PATH", "/nonexistent/gh")
      assert {:error, _reason} = GhReadIssue.run(%{repo_path: "/tmp", number: 1}, %{})
    end
  end
end
