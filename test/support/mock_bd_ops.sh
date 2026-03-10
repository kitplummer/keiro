#!/usr/bin/env bash
# Mock bd CLI that returns ops-labeled beads for testing ops dispatch path.
set -e

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-300","title":"Deploy: Add login page","description":"Deploy changes to fly.io and verify smoke tests.","status":"open","priority":2,"type":"task","labels":["ops"],"dependencies":[],"created_at":"2026-03-10T10:00:00Z"}]
EOF
    ;;
  list)
    cat <<'EOF'
[{"id":"gl-300","title":"Deploy: Add login page","description":"Deploy changes to fly.io and verify smoke tests.","status":"open","priority":2,"type":"task","labels":["ops"],"dependencies":[],"created_at":"2026-03-10T10:00:00Z"}]
EOF
    ;;
  update)
    echo "Updated $2"
    ;;
  close)
    echo "Closed $2"
    ;;
  create)
    echo "gl-400"
    ;;
  link)
    echo "Linked $2 -> $3"
    ;;
  comments)
    echo "Comment added"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
