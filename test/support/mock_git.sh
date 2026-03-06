#!/usr/bin/env bash
# Mock git CLI for testing.
set -e

case "$1" in
  checkout)
    if [ "$2" = "-b" ]; then
      echo "Switched to a new branch '$3'"
    else
      echo "Switched to branch '$2'"
    fi
    ;;
  pull)
    echo "Already up to date."
    ;;
  add)
    shift
    echo "Added: $*"
    ;;
  commit)
    # Extract message from -m flag
    shift  # drop "commit"
    msg=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -m) msg="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    echo "[eng/test-branch abc1234] $msg"
    echo " 1 file changed, 10 insertions(+)"
    ;;
  push)
    echo "To github.com:test/repo.git"
    echo " * [new branch]      $3 -> $3"
    ;;
  status)
    echo "On branch main"
    echo "nothing to commit, working tree clean"
    ;;
  diff)
    echo ""
    ;;
  log)
    echo "abc1234 Initial commit"
    ;;
  *)
    echo "Unknown git command: $1" >&2
    exit 1
    ;;
esac
