#!/usr/bin/env bash
# Mock bd CLI for task-schema tests. Returns eng-labeled beads and logs mutations.
set -e

LOG="${MOCK_BD_LOG:-/dev/null}"

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-100","title":"Implement widget","description":"Build a widget","status":"open","priority":1,"type":"task","labels":["eng"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"}]
EOF
    ;;
  list)
    cat <<'EOF'
[{"id":"gl-100","title":"Implement widget","description":"Build a widget","status":"open","priority":1,"type":"task","labels":["eng"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"},{"id":"gl-101","title":"Refactor parser","status":"in_progress","priority":2,"type":"task","labels":["eng"],"dependencies":[],"created_at":"2026-03-05T11:00:00Z"}]
EOF
    ;;
  update)
    echo "$@" >> "$LOG"
    echo "Updated $2"
    ;;
  close)
    echo "$@" >> "$LOG"
    echo "Closed $2"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
