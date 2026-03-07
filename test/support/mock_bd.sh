#!/usr/bin/env bash
# Mock bd CLI for testing. Routes on first argument.
set -e

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  create)
    # Output the bead ID (mimics --silent mode)
    echo "gl-001"
    ;;
  update)
    echo "Updated $2"
    ;;
  close)
    echo "Closed $2"
    ;;
  list)
    cat <<'EOF'
[{"id":"gl-001","title":"Fix crash-loop","status":"open","priority":0,"type":"bug","labels":["ops"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"},{"id":"gl-002","title":"Add monitoring","status":"in_progress","priority":2,"type":"task","labels":["ops"],"dependencies":[{"target_id":"gl-001","dep_type":"blocks"}],"created_at":"2026-03-05T11:00:00Z"}]
EOF
    ;;
  ready)
    cat <<'EOF'
[{"id":"gl-001","title":"Fix crash-loop","status":"open","priority":0,"type":"bug","labels":["ops"],"dependencies":[],"created_at":"2026-03-05T10:00:00Z"}]
EOF
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
