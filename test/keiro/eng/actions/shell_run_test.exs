defmodule Keiro.Eng.Actions.ShellRunTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.Actions.ShellRun

  @tmp_dir System.tmp_dir!()

  describe "allowlisted commands" do
    test "auto-approves git status without governance" do
      assert {:ok, result} = ShellRun.run(%{command: "git status", repo_path: @tmp_dir}, %{})
      assert is_integer(result.exit_code)
      assert is_binary(result.output)
    end

    test "auto-approves git diff" do
      assert {:ok, result} = ShellRun.run(%{command: "git diff", repo_path: @tmp_dir}, %{})
      assert is_integer(result.exit_code)
    end

    test "auto-approves git log" do
      assert {:ok, result} = ShellRun.run(%{command: "git log", repo_path: @tmp_dir}, %{})
      assert is_integer(result.exit_code)
    end
  end

  describe "non-allowlisted commands" do
    test "requires approval for arbitrary commands" do
      approve = %{approve_fn: fn _desc -> :approved end}

      assert {:ok, result} = ShellRun.run(%{command: "echo hello", repo_path: @tmp_dir}, approve)
      assert result.exit_code == 0
      assert result.output == "hello"
    end

    test "rejects when governance gate rejects" do
      reject = %{approve_fn: fn _desc -> :rejected end}

      assert {:error, msg} = ShellRun.run(%{command: "echo nope", repo_path: @tmp_dir}, reject)
      assert msg =~ "Rejected by governance gate"
    end
  end

  describe "error handling" do
    test "returns non-zero exit code for failing commands" do
      approve = %{approve_fn: fn _desc -> :approved end}

      assert {:ok, result} =
               ShellRun.run(%{command: "false", repo_path: @tmp_dir}, approve)

      assert result.exit_code != 0
    end
  end
end
