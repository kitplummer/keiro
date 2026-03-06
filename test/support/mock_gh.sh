#!/usr/bin/env bash
# Mock gh CLI for testing.
set -e

case "$1" in
  pr)
    case "$2" in
      create)
        echo "https://github.com/test/repo/pull/42"
        ;;
      list)
        cat <<'EOF'
[{"number":10,"title":"feat: add scanner","state":"OPEN","labels":[{"name":"eng"}],"author":{"login":"dev1"},"createdAt":"2026-03-01T10:00:00Z"},{"number":11,"title":"fix: deploy config","state":"OPEN","labels":[{"name":"ops"}],"author":{"login":"dev2"},"createdAt":"2026-03-02T12:00:00Z"}]
EOF
        ;;
      *)
        echo "Unknown gh pr subcommand: $2" >&2
        exit 1
        ;;
    esac
    ;;
  issue)
    case "$2" in
      list)
        cat <<'EOF'
[{"number":1,"title":"Add authentication","body":"We need auth","state":"OPEN","labels":[{"name":"feature"}],"createdAt":"2026-03-01T10:00:00Z","author":{"login":"legit-user"}},{"number":2,"title":"Fix deployment crash","body":"App crashes on deploy","state":"OPEN","labels":[{"name":"bug"}],"createdAt":"2026-03-01T11:00:00Z","author":{"login":"legit-user"}},{"number":3,"title":"asdkjhasd","body":"xyzxyzxyz","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:00:00Z","author":{"login":"spammer"}},{"number":4,"title":"qwerty123","body":"asdfasdf","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:01:00Z","author":{"login":"spammer"}},{"number":5,"title":"zzzzzz","body":"aaabbb","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:02:00Z","author":{"login":"spammer"}},{"number":6,"title":"xxxxxx","body":"yyyyyy","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:03:00Z","author":{"login":"spammer"}},{"number":7,"title":"bbbbbb","body":"cccccc","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:04:00Z","author":{"login":"spammer"}},{"number":8,"title":"eeeeee","body":"ffffff","state":"OPEN","labels":[],"createdAt":"2026-03-05T08:05:00Z","author":{"login":"spammer"}}]
EOF
        ;;
      view)
        cat <<'EOF'
{"number":1,"title":"Add authentication","body":"We need auth for the API","state":"OPEN","labels":[{"name":"feature"}],"comments":[{"body":"Good idea","author":{"login":"reviewer"}}],"author":{"login":"legit-user"},"createdAt":"2026-03-01T10:00:00Z"}
EOF
        ;;
      *)
        echo "Unknown gh issue subcommand: $2" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unknown gh command: $1" >&2
    exit 1
    ;;
esac
