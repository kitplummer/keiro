defmodule Keiro.Arch.Actions.GhListPrsTest do
  use ExUnit.Case, async: false

  alias Keiro.Arch.Actions.GhListPrs

  @mock_gh Path.expand("../../../support/mock_gh.sh", __DIR__)

  setup do
    System.put_env("GH_BIN_PATH", @mock_gh)
    on_exit(fn -> System.delete_env("GH_BIN_PATH") end)
    :ok
  end

  describe "run/2" do
    test "lists PRs with parsed JSON" do
      assert {:ok, result} = GhListPrs.run(%{repo_path: "/tmp"}, %{})
      assert is_list(result.prs)
      assert result.count == length(result.prs)
      assert result.count > 0
    end

    test "PRs contain expected fields" do
      assert {:ok, result} = GhListPrs.run(%{repo_path: "/tmp"}, %{})
      pr = List.first(result.prs)
      assert Map.has_key?(pr, "number")
      assert Map.has_key?(pr, "title")
      assert Map.has_key?(pr, "author")
      assert Map.has_key?(pr, "state")
    end

    test "returns error when gh CLI not found" do
      System.put_env("GH_BIN_PATH", "/nonexistent/gh")
      assert {:error, _reason} = GhListPrs.run(%{repo_path: "/tmp"}, %{})
    end
  end
end
