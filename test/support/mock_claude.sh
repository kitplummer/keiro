#!/usr/bin/env bash
# Mock claude CLI for testing.
# Emits NDJSON events matching claude --print --output-format stream-json.
set -e

# Parse args to find the prompt
PROMPT=""
OUTPUT_FORMAT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print) shift ;;
    -p) PROMPT="$2"; shift 2 ;;
    --output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
    --verbose) shift ;;
    --allowedTools) shift 2 ;;
    --max-turns) shift 2 ;;
    --permission-mode) shift 2 ;;
    *) shift ;;
  esac
done

if [[ "$PROMPT" == *"FAIL"* ]]; then
  echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"test"}'
  echo '{"type":"result","subtype":"error","is_error":true,"result":"Something went wrong","duration_ms":100,"num_turns":1,"total_cost_usd":0.01,"session_id":"test"}'
  exit 1
fi

if [[ "$PROMPT" == *"SLOW"* ]]; then
  sleep 30
  echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"test"}'
  echo '{"type":"result","subtype":"success","is_error":false,"result":"Changes applied after delay","duration_ms":30000,"num_turns":8,"total_cost_usd":0.26,"session_id":"test"}'
  exit 0
fi

if [[ "$PROMPT" == *"CHUNKED"* ]]; then
  # Simulates Claude producing NDJSON events in chunks (resets idle timer).
  echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"test"}'
  sleep 0.3
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Reading files..."}]},"session_id":"test"}'
  sleep 0.3
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"lib/app.ex"}}]},"session_id":"test"}'
  sleep 0.3
  echo '{"type":"result","subtype":"success","is_error":false,"result":"Changes applied with chunks","duration_ms":5000,"num_turns":12,"total_cost_usd":0.30,"session_id":"test"}'
  exit 0
fi

if [[ "$PROMPT" == *"RAW_TEXT"* ]]; then
  echo "This is plain text, not JSON"
  exit 0
fi

if [[ "$PROMPT" == *"ERROR_RESULT"* ]]; then
  echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"test"}'
  echo '{"type":"result","subtype":"error","is_error":true,"result":"Tool execution failed: permission denied","duration_ms":500,"num_turns":1,"total_cost_usd":0.02,"session_id":"test"}'
  exit 0
fi

# Default: return valid NDJSON stream
echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"test"}'
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"I will implement this."}]},"session_id":"test"}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"Changes applied successfully","duration_ms":70000,"num_turns":8,"total_cost_usd":0.26,"session_id":"test"}'
