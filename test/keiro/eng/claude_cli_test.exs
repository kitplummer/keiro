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
      assert {:ok, result} =
               ClaudeCli.run("implement this", System.tmp_dir!(), bin: @mock_claude)

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

  describe "idle timeout" do
    test "kills process after idle_timeout with no output" do
      assert {:error, msg} =
               ClaudeCli.run("SLOW task", System.tmp_dir!(),
                 bin: @mock_claude,
                 idle_timeout: 200
               )

      assert msg =~ "idle for 200ms"
    end

    test "legacy :timeout option works as idle_timeout" do
      assert {:error, msg} =
               ClaudeCli.run("SLOW task", System.tmp_dir!(),
                 bin: @mock_claude,
                 timeout: 200
               )

      assert msg =~ "idle for 200ms"
    end

    test "chunked output resets idle timer — process completes" do
      # CHUNKED mock sends data every 300ms. With a 500ms idle_timeout,
      # each chunk resets the timer so it never fires.
      assert {:ok, result} =
               ClaudeCli.run("CHUNKED output", System.tmp_dir!(),
                 bin: @mock_claude,
                 idle_timeout: 500
               )

      assert result["result"] == "Changes applied with chunks"
    end

    test "respects CLAUDE_IDLE_TIMEOUT_MS env var" do
      System.put_env("CLAUDE_IDLE_TIMEOUT_MS", "200")

      try do
        assert {:error, msg} =
                 ClaudeCli.run("SLOW task", System.tmp_dir!(), bin: @mock_claude)

        assert msg =~ "idle for 200ms"
      after
        System.delete_env("CLAUDE_IDLE_TIMEOUT_MS")
      end
    end

    test "falls back to CLAUDE_TIMEOUT_MS env var for backward compat" do
      System.put_env("CLAUDE_TIMEOUT_MS", "200")

      try do
        assert {:error, msg} =
                 ClaudeCli.run("SLOW task", System.tmp_dir!(), bin: @mock_claude)

        assert msg =~ "idle for 200ms"
      after
        System.delete_env("CLAUDE_TIMEOUT_MS")
      end
    end
  end

  describe "max timeout" do
    test "kills process after max_timeout even with output" do
      # CHUNKED sends output but max_timeout is very short
      assert {:error, msg} =
               ClaudeCli.run("CHUNKED output", System.tmp_dir!(),
                 bin: @mock_claude,
                 idle_timeout: 5_000,
                 max_timeout: 200
               )

      assert msg =~ "max timeout"
    end

    test "respects CLAUDE_MAX_TIMEOUT_MS env var" do
      System.put_env("CLAUDE_MAX_TIMEOUT_MS", "200")

      try do
        assert {:error, msg} =
                 ClaudeCli.run("CHUNKED output", System.tmp_dir!(),
                   bin: @mock_claude,
                   idle_timeout: 5_000
                 )

        assert msg =~ "max timeout"
      after
        System.delete_env("CLAUDE_MAX_TIMEOUT_MS")
      end
    end
  end
end
