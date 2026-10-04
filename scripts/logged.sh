#!/bin/bash
# Runs a command with its output shown as usual and also saved to .build/logs/<name>.log,
# then summarizes it into .build/logs/summary.md. Builds and tests often run in Terminal
# (Claude Code's sandbox can't run them); the summary lets an agent read the results
# afterwards instead of someone pasting them.
#
# Usage: scripts/logged.sh <name> <command> [args...]   (exits with the command's status)
#
# The Makefile exports LOG_RUN once per `make` invocation. summary.md lists the targets of
# that run first and marks older summaries as earlier runs, so a target that didn't run
# this time can't look like it passed. Output goes through `tee`, so commands don't see a
# terminal: swift test prints without colour and in bursts, which isn't a hang. When the
# command ends, the summary of this run's targets so far is printed too, so the end of
# `make test` shows both test-core and test-app.
set -uo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <name> <command> [args...]" >&2; exit 2; }
name=$1
shift
run=${LOG_RUN:-single-$$}
dir=.build/logs
here=$(dirname "$0")
mkdir -p "$dir"
log="$dir/$name.log"

# Rebuilds summary.md from the per-target summaries: this run first, then earlier runs.
write_summary() {
  local f n r current="" earlier=""
  for f in $(ls -t "$dir"/*.summary 2>/dev/null); do
    n=$(basename "$f" .summary)
    r=$(cat "$dir/$n.run" 2>/dev/null)
    if [ "$r" = "$run" ]; then current="$current $f"; else earlier="$earlier $f"; fi
  done
  {
    echo "# Build and test summary"
    echo
    echo "Updated $(date '+%Y-%m-%d %H:%M:%S'), run \`$run\`. Full logs: \`.build/logs/<target>.log\`."
    for f in $current; do
      echo
      cat "$f"
    done
    if [ -n "$earlier" ]; then
      echo
      echo "# Earlier runs (not part of this run)"
      for f in $earlier; do
        echo
        cat "$f"
      done
    fi
  } >"$dir/summary.md.tmp" && mv "$dir/summary.md.tmp" "$dir/summary.md"
}

# Until the command finishes, this target shows as unfinished, so an interrupted run
# can't leave an older PASS in its place.
echo "$run" >"$dir/$name.run"
printf '## %s: did not finish (interrupted or still running)\n' "$name" >"$dir/$name.summary"
write_summary

{
  echo "\$ $*"
  echo "started $(date '+%Y-%m-%d %H:%M:%S')"
  [ "${SANDBOX_RUNTIME:-}" = 1 ] && echo "sandbox: Claude Code"
} >"$log"
"$@" 2>&1 | tee -a "$log"
status=${PIPESTATUS[0]}
echo "exit $status" >>"$log"

"$here/summarize-log.sh" "$name" "$status" >"$dir/$name.summary.tmp" &&
  mv "$dir/$name.summary.tmp" "$dir/$name.summary"
write_summary

# This run's targets, oldest first, so the last one finished is at the bottom.
print_run_summary() {
  local f n files="" total=0 failed=0 title colour rule bold="" dim="" green="" red="" reset=""
  if [ -t 1 ]; then
    bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' red=$'\e[31m' reset=$'\e[0m'
  fi
  for f in $(ls -tr "$dir"/*.summary 2>/dev/null); do
    n=$(basename "$f" .summary)
    [ "$(cat "$dir/$n.run" 2>/dev/null)" = "$run" ] || continue
    files="$files $f"
    total=$((total + 1))
    head -1 "$f" | grep -q ': PASS$' || failed=$((failed + 1))
  done
  if [ "$failed" -eq 0 ]; then
    colour=$green
    if [ "$total" -eq 1 ]; then title="✔ Passed"; else title="✔ All $total targets passed"; fi
  else
    colour=$red title="✘ $failed of $total targets failed"
    [ "$total" -eq 1 ] && title="✘ Failed"
  fi
  rule="────────────────────────────────────────────────────────────"
  echo
  echo "${dim}${rule}${reset}"
  echo "  ${bold}${colour}${title}${reset}${dim}  ·  summary of this run${reset}"
  echo "${dim}${rule}${reset}"
  for f in $files; do
    echo
    sed -E \
      -e "s/^## (.*): PASS$/${bold}\\1: ${green}PASS${reset}/" \
      -e "s/^## (.*): (FAIL.*|did not finish.*)$/${bold}\\1: ${red}\\2${reset}/" \
      -e "s/^### (.*)$/${bold}\\1${reset}/" "$f"
  done
  echo
  echo "${dim}Saved to $dir/summary.md; full logs in $dir/<target>.log${reset}"
}
print_run_summary

exit "$status"
