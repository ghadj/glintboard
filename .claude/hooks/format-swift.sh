#!/bin/bash
# PostToolUse hook: format a Swift file right after Claude edits it.
# Never blocks: formatting problems are reported by lint, not here.

input=$(cat)
file=$(printf '%s' "$input" | /usr/bin/python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
except Exception:
    print("")
')

case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0
xcrun --find swift-format >/dev/null 2>&1 || exit 0
xcrun swift-format format --in-place "$file" >/dev/null 2>&1 || true
exit 0
