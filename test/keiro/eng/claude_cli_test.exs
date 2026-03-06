defmodule Keiro.Eng.ClaudeCliTest do
  use ExUnit.Case, async: true

  alias Keiro.Eng.ClaudeCli

  @mock_claude Path.expand("../../support/mock_claude.sh", __DIR__)

  describe "claude_path/0" do
    test "returns a string path" do
      assert is_binary(ClaudeCli.claude_path())
    end

    test "defaults to claude when no env or config" do
      # Clear env for this check
      original = System.get_env("CLAUDE_BIN_PATH")
      System.delete_env("CLAUDE_BIN_PATH")

      try do
        path = ClaudeCli.claude_path()
        assert is_binary(path)
      after
        if original, do: System.put_env("CLAUDE_BIN_PATH", original)
      end
    end
  end

  describe "run/3" do
    test "returns parsed JSON on success" do
      assert {:ok, result} = ClaudeCli.run("implement this", System.tmp_dir!(), bin: @mock_claude)
      assert result["result"] == "Changes applied successfully"
      assert result["cost_usd"] == 0.26
      assert result["num_turns"] == 8
    end

    test "returns error when binary not found" do
      assert {:error, "claude CLI not found:" <> _} =
               ClaudeCli.run("test", System.tmp_dir!(), bin: "/no/such/claude")
    end

    test "returns error on non-zero exit code" do
      assert {:error, msg} =
               ClaudeCli.run("FAIL this task", System.tmp_dir!(), bin: @mock_claude)

      assert msg =~ "claude exited with code"
    end

    test "handles non-JSON stdout gracefully" do
      assert {:ok, result} =
               ClaudeCli.run("RAW_TEXT output", System.tmp_dir!(), bin: @mock_claude)

      assert result["parse_error"] == true
      assert is_binary(result["result"])
    end

    test "accepts custom allowed_tools option" do
      assert {:ok, _} =
               ClaudeCli.run("implement this", System.tmp_dir!(),
                 bin: @mock_claude,
                 allowed_tools: "Edit,Read"
               )
    end

    test "accepts custom max_turns option" do
      assert {:ok, _} =
               ClaudeCli.run("implement this", System.tmp_dir!(),
                 bin: @mock_claude,
                 max_turns: "10"
               )
    end
  end
end
