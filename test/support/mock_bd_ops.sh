#!/usr/bin/env bash
# Mock bd CLI that returns an ops-labeled bead and logs lifecycle calls.
set -e

LOG="${MOCK_BD_LOG:-/dev/null}"

case "$1" in
  --version)
    echo "bd 0.49.3 (mock-ops)"
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-200","title":"Fix crash-loop","status":"open","priority":0,"type":"bug","labels":["ops"],"dependencies":[],"created_at":"2026-03-06T10:00:00Z"}]
EOF
    ;;
  update)
    echo "update $2 $3 $4" >> "$LOG"
    echo "Updated $2"
    ;;
  close)
    echo "close $2" >> "$LOG"
    echo "Closed $2"
    ;;
  list)
    cat <<'EOF'
[{"id":"gl-200","title":"Fix crash-loop","status":"open","priority":0,"type":"bug","labels":["ops"],"dependencies":[],"created_at":"2026-03-06T10:00:00Z"}]
EOF
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
