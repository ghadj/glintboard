#!/bin/bash
# Stop hook: when Swift sources have changed, don't let Claude finish while
# ScrapKit tests fail. Exit code 2 sends the failure back to Claude.
#
# If Claude is already continuing because of this hook (stop_hook_active),
# let it stop rather than loop forever; CI is the backstop.

input=$(cat)
active=$(printf '%s' "$input" | /usr/bin/python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get("stop_hook_active", False))
except Exception:
    print(False)
')
[ "$active" = "True" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git rev-parse --verify HEAD >/dev/null 2>&1 || exit 0
[ -d Packages/ScrapKit ] || exit 0

changed=$(git diff --name-only HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift')
[ -z "$changed" ] && exit 0

if ! out=$(swift test --package-path Packages/ScrapKit --parallel 2>&1); then
  echo "ScrapKit tests are failing. Fix them before finishing (or explain why you can't):" >&2
  printf '%s\n' "$out" | tail -n 40 >&2
  exit 2
fi
exit 0
