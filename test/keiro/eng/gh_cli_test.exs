defmodule Keiro.Eng.GhCliTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.GhCli

  @mock_gh Path.expand("../../support/mock_gh.sh", __DIR__)

  describe "run/3" do
    test "runs gh command and returns stdout" do
      assert {:ok, output} = GhCli.run(@mock_gh, ["pr", "create"])
      assert output =~ "github.com/test/repo/pull/42"
    end

    test "returns error for unknown commands" do
      assert {:error, output} = GhCli.run(@mock_gh, ["bogus"])
      assert output =~ "Unknown gh command"
    end

    test "returns error when binary not found" do
      assert {:error, "gh CLI not found:" <> _} = GhCli.run("/no/such/gh", ["pr", "create"])
    end

    test "supports cd option" do
      assert {:ok, _output} = GhCli.run(@mock_gh, ["pr", "create"], cd: System.tmp_dir!())
    end
  end

  describe "gh_path/0" do
    test "returns a string path" do
      assert is_binary(GhCli.gh_path())
    end
  end
end
