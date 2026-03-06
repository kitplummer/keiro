#!/usr/bin/env bash
# Mock gh CLI for testing.
set -e

case "$1" in
  pr)
    case "$2" in
      create)
        echo "https://github.com/test/repo/pull/42"
        ;;
      *)
        echo "Unknown gh pr subcommand: $2" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unknown gh command: $1" >&2
    exit 1
    ;;
esac
