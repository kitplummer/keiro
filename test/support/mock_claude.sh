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

if [[ "$PROMPT" == *"RAW_TEXT"* ]]; then
  echo "This is plain text, not JSON"
  exit 0
fi

# Default: return valid JSON result
cat <<'EOF'
{"result":"Changes applied successfully","cost_usd":0.26,"duration_ms":70000,"num_turns":8}
EOF
