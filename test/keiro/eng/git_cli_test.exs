defmodule Keiro.Eng.GitCliTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.GitCli

  @mock_git Path.expand("../../support/mock_git.sh", __DIR__)

  describe "run/3" do
    test "runs git command and returns stdout" do
      assert {:ok, output} = GitCli.run(@mock_git, ["status"])
      assert output =~ "On branch main"
    end

    test "returns error for unknown commands" do
      assert {:error, output} = GitCli.run(@mock_git, ["bogus"])
      assert output =~ "Unknown git command"
    end

    test "returns error when binary not found" do
      assert {:error, "git CLI not found:" <> _} = GitCli.run("/no/such/git", ["status"])
    end

    test "supports cd option" do
      assert {:ok, _output} = GitCli.run(@mock_git, ["status"], cd: System.tmp_dir!())
    end
  end

  describe "git_path/0" do
    test "returns a string path" do
      assert is_binary(GitCli.git_path())
    end
  end
end
