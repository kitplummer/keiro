#!/usr/bin/env bash
# Mock bd CLI that returns eng-labeled beads for testing engineer pipeline path.
set -e

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-100","title":"Add login page","description":"Build a login page with email/password.","status":"open","priority":2,"type":"task","labels":["eng"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"}]
EOF
    ;;
  list)
    cat <<'EOF'
[{"id":"gl-100","title":"Add login page","description":"Build a login page with email/password.","status":"open","priority":2,"type":"task","labels":["eng"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"}]
EOF
    ;;
  update)
    echo "Updated $2"
    ;;
  close)
    echo "Closed $2"
    ;;
  create)
    echo "gl-200"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
