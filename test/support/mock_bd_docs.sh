#!/usr/bin/env bash
# Mock bd CLI that returns docs-labeled beads (no matching agent).
set -e

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-300","title":"Write docs","description":"Write the docs.","status":"open","priority":3,"type":"task","labels":["docs"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"}]
EOF
    ;;
  update)
    echo "Updated $2"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
