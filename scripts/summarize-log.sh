#!/bin/bash
# Prints a short Markdown summary of one log written by scripts/logged.sh: the result,
# test counts, failing or skipped tests, errors, and warnings worth reading.
#
# Usage: scripts/summarize-log.sh <name> <exit status>   (reads .build/logs/<name>.log)
set -uo pipefail
name=$1
status=$2
log=".build/logs/$name.log"
[ -f "$log" ] || { echo "## $name: no log"; exit 0; }

# Known harmless noise: xcodebuild's destination note and the App Intents metadata step.
harmless='Using the first of multiple matching destinations|Metadata extraction skipped, no AppIntents'

when=$(sed -n 's/^started //p' "$log" | head -1)
if [ "$status" -eq 0 ]; then result=PASS; else result="FAIL (exit $status)"; fi
echo "## $name: $result"
echo
echo "- Command: \`$(head -1 "$log" | sed 's/^\$ //' | cut -c1-200)\`, started $when"
if [ "$status" -ne 0 ] && grep -q '^sandbox: Claude Code$' "$log"; then
  echo "- Ran inside Claude Code's sandbox, which blocks builds and tests; rerun in Terminal for real results"
fi

# Swift Testing (swift test): one "Test run with N tests" line per test product.
core=$(grep -E '(✔|✘) Test run with [0-9]+ tests?' "$log" | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | awk '{ s += $1 } END { if (NR) print s }')
if [ -n "$core" ]; then
  echo "- Swift Testing: $core tests in $(grep -cE '(✔|✘) Test run with' "$log") runs"
elif [ "$name" = test-core ] || [ "$name" = bootstrap ]; then
  echo "- Swift Testing: no test count found in the log"
fi

# xcodebuild test: one "Test case '…' passed|failed|skipped" line per test case.
passed=$(grep -cE "^Test case '.*' passed" "$log")
failed=$(grep -cE "^Test case '.*' failed" "$log")
skipped=$(grep -cE "^Test case '.*' skipped" "$log")
[ $((passed + failed + skipped)) -gt 0 ] && echo "- Xcode tests: $passed passed, $failed failed, $skipped skipped"
grep -oE '\*\* (TEST|BUILD) (SUCCEEDED|FAILED) \*\*' "$log" | sort -u | sed 's/^/- /'
grep -E '(lint|check|self-test) passed$' "$log" | sed 's/^/- /'

section() { # section <title> <lines>
  [ -n "$2" ] || return 0
  echo
  echo "### $1"
  echo
  # Long lines (compiler invocations) are cut; the full text is in the log.
  printf '%s\n' "$2" | head -20 | awk '{ print "    " (length($0) > 300 ? substr($0, 1, 300) " …" : $0) }'
  [ "$(printf '%s\n' "$2" | wc -l)" -gt 20 ] && echo "    … (more in $log)"
}
section "Failing or skipped tests" "$(grep -E "^Test case '.*' (failed|skipped)|✘ Test |FAIL  " "$log")"
section "Errors" "$(grep -E 'error:|^error' "$log" | grep -vE "$harmless" | sort -u)"
section "Warnings" "$(grep -E 'warning:' "$log" | grep -vE "$harmless" | sort -u)"
if [ "$status" -ne 0 ]; then
  # bootstrap.sh colours its output; strip the escape codes.
  section "Last lines" "$(tail -15 "$log" | sed $'s/\x1b\\[[0-9;]*m//g')"
fi
exit 0
