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
# terminal: swift test prints without colour and in bursts, which isn't a hang.
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

exit "$status"
