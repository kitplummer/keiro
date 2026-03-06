#!/usr/bin/env bash
# Mock fly CLI for testing.
set -e

case "$1" in
  status)
    cat <<'EOF'
{"Name":"lowendinsight","Status":"running","Hostname":"lowendinsight.fly.dev","Machines":[{"id":"abc123","state":"started"}]}
EOF
    ;;
  logs)
    cat <<'EOF'
2026-03-05T10:00:00Z app[abc123] Starting
2026-03-05T10:00:01Z app[abc123] Listening on 0.0.0.0:4000
2026-03-05T10:00:02Z app[abc123] Health check passed
EOF
    ;;
  ssh)
    echo "command output from container"
    ;;
  deploy)
    echo "Deploying... done! Image: registry.fly.io/lowendinsight:latest"
    ;;
  *)
    echo "Unknown fly command: $1" >&2
    exit 1
    ;;
esac
