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
    test "returns parsed NDJSON result on success" do
      assert {:ok, result} =
               ClaudeCli.run("implement this", System.tmp_dir!(), bin: @mock_claude)

      assert result["result"] == "Changes applied successfully"
      assert result["cost_usd"] == 0.26
      assert result["num_turns"] == 8
      assert result["duration_ms"] == 70_000
      assert result["session_id"] == "test"
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

    test "returns error when result event has is_error true (exit 0)" do
      assert {:error, msg} =
               ClaudeCli.run("ERROR_RESULT test", System.tmp_dir!(), bin: @mock_claude)

      assert msg =~ "permission denied"
    end

    test "handles non-JSON stdout gracefully (legacy fallback)" do
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

    test "chunked NDJSON events reset idle timer — process completes" do
      # CHUNKED mock sends NDJSON events every 300ms. With a 500ms idle_timeout,
      # each event resets the timer so it never fires.
      assert {:ok, result} =
               ClaudeCli.run("CHUNKED output", System.tmp_dir!(),
                 bin: @mock_claude,
                 idle_timeout: 500
               )

      assert result["result"] == "Changes applied with chunks"
      assert result["num_turns"] == 12
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

  describe "parse_stream_result/1" do
    test "extracts result from NDJSON stream" do
      stream = """
      {"type":"system","subtype":"init","cwd":"/tmp","session_id":"s1"}
      {"type":"assistant","message":{"content":[{"type":"text","text":"Working..."}]},"session_id":"s1"}
      {"type":"result","subtype":"success","is_error":false,"result":"Done","duration_ms":1000,"num_turns":3,"total_cost_usd":0.05,"session_id":"s1"}
      """

      assert {:ok, result} = ClaudeCli.parse_stream_result(stream)
      assert result["result"] == "Done"
      assert result["cost_usd"] == 0.05
      assert result["num_turns"] == 3
      assert result["duration_ms"] == 1000
      assert result["session_id"] == "s1"
    end

    test "returns error for is_error result events" do
      stream = """
      {"type":"system","subtype":"init","cwd":"/tmp","session_id":"s1"}
      {"type":"result","subtype":"error","is_error":true,"result":"failed hard","duration_ms":100,"num_turns":1,"total_cost_usd":0.01,"session_id":"s1"}
      """

      assert {:error, "failed hard"} = ClaudeCli.parse_stream_result(stream)
    end

    test "falls back to legacy JSON parsing when no NDJSON events" do
      output = ~s|{"result":"legacy output","cost_usd":0.10,"num_turns":2}|

      assert {:ok, result} = ClaudeCli.parse_stream_result(output)
      assert result["result"] == "legacy output"
    end

    test "handles plain text fallback" do
      assert {:ok, result} = ClaudeCli.parse_stream_result("just some text\n")
      assert result["parse_error"] == true
      assert result["result"] == "just some text"
    end
  end
end
