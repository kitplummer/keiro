#!/usr/bin/env bash
# Mock bd CLI that returns empty ready list.
set -e

case "$1" in
  --version)
    echo "bd 0.49.3"
    ;;
  ready)
    echo "[]"
    ;;
  list)
    echo "[]"
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 1
    ;;
esac
