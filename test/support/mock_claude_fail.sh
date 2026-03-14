#!/usr/bin/env bash
# Mock claude CLI that always fails with NDJSON error.
echo '{"type":"system","subtype":"init","cwd":"/tmp","session_id":"fail"}'
echo '{"type":"result","subtype":"error","is_error":true,"result":"Something went wrong","duration_ms":100,"num_turns":1,"total_cost_usd":0.01,"session_id":"fail"}'
exit 1
