#!/usr/bin/env bash
# Mock claude CLI for testing.
set -e

# Parse args to find the prompt
PROMPT=""
OUTPUT_FORMAT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print) shift ;;
    -p) PROMPT="$2"; shift 2 ;;
    --output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
    --allowedTools) shift 2 ;;
    --max-turns) shift 2 ;;
    --permission-mode) shift 2 ;;
    *) shift ;;
  esac
done

if [[ "$PROMPT" == *"FAIL"* ]]; then
  echo "Something went wrong" >&2
  exit 1
fi

if [[ "$PROMPT" == *"SLOW"* ]]; then
  sleep 30
  cat <<'EOF'
{"result":"Changes applied after delay","cost_usd":0.26,"duration_ms":30000,"num_turns":8}
EOF
  exit 0
fi

if [[ "$PROMPT" == *"CHUNKED"* ]]; then
  # Simulates Claude producing output in chunks (resets idle timer).
  # Real claude --print --output-format json sends progress to stderr
  # and final JSON to stdout. We send chunks to stdout to exercise the
  # Port data path, but the final output is valid JSON.
  echo -n '{"progress":"' >&1
  sleep 0.3
  echo -n 'reading...' >&1
  sleep 0.3
  echo -n 'writing...' >&1
  sleep 0.3
  echo -n '","result":"Changes applied with chunks","cost_usd":0.30,"duration_ms":5000,"num_turns":12}' >&1
  echo "" >&1
  exit 0
fi

if [[ "$PROMPT" == *"RAW_TEXT"* ]]; then
  echo "This is plain text, not JSON"
  exit 0
fi

# Default: return valid JSON result
cat <<'EOF'
{"result":"Changes applied successfully","cost_usd":0.26,"duration_ms":70000,"num_turns":8}
EOF
