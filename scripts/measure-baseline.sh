#!/bin/bash
# Measures a Release build on this Mac: launch to menu bar icon (NFR-4) and idle physical
# footprint (NFR-2). Prints a summary and writes rows for docs/perf.md to
# .build/perf/latest.md; with --record it also appends them to docs/perf.md.
#
# Usage: scripts/measure-baseline.sh [--milestone M1] [--runs 5] [--idle 60] [--record]
#
# It builds, launches, and quits the app, so run it in Terminal, not inside Claude Code's
# sandbox. Launch time is measured from a marker written to the system log just before
# `open` to the app's "Launched: status item installed" line (AppDelegate), so both
# timestamps come from the same clock. Uses only macOS and Xcode tools.
#
# Note: it quits any running copy (release or Dev), and it runs the Release build, which
# has the production bundle id, so it uses the real app's preferences, permissions, and
# (from M1) data folder. XCB_FLAGS (as for make build) are passed to xcodebuild, so
# contributors without a Team ID can sign ad hoc.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

args="$*"
milestone="-"
runs=5
idle=60
record=0
usage() { echo "usage: $0 [--milestone M1] [--runs 5] [--idle 60] [--record]"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --milestone) milestone=${2:-}; shift ;;
    --runs) runs=${2:-}; shift ;;
    --idle) idle=${2:-}; shift ;;
    --record) record=1 ;;
    *) usage ;;
  esac
  shift
done
[[ $runs =~ ^[1-9][0-9]*$ && $idle =~ ^[0-9]+$ ]] || usage
# A milestone id (M0, M1, ...) or "-"; anything else would break the Markdown row.
[[ $milestone =~ ^(-|M[0-9]+)$ ]] || usage

fail() { echo "error: $1" >&2; exit 1; }

if [ "${SANDBOX_RUNTIME:-}" = 1 ]; then
  echo "error: running inside Claude Code's sandbox, which blocks building and launching the app." >&2
  echo "Run it in Terminal instead: make perf PERF_FLAGS=\"$args\"" >&2
  exit 2
fi

cfg=Config/Branding.xcconfig
setting() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$cfg" | head -1 | sed 's/[[:space:]]*$//'; }
name=$(setting APP_DISPLAY_NAME)
bundle_id=$(setting APP_BUNDLE_ID)
[ -n "$name" ] && [ -n "$bundle_id" ] || fail "APP_DISPLAY_NAME or APP_BUNDLE_ID missing from $cfg"
app=".build/xcode/Build/Products/Release/$name.app"

echo "Building the Release app"
# Word splitting is intended: XCB_FLAGS holds several build settings.
xcodebuild -project App.xcodeproj -scheme App -configuration Release -derivedDataPath .build/xcode ${XCB_FLAGS:-} build -quiet \
  || fail "Release build failed"
[ -d "$app" ] || fail "$app not found after the build"

# Processes are matched by executable path, not name: macOS cuts process names to
# 16 characters, so a longer display name wouldn't match.
release_exe="/$name.app/Contents/MacOS/$name"
dev_exe="/$name Dev.app/Contents/MacOS/$name Dev"
running() { pgrep -f -- "$release_exe" >/dev/null || pgrep -f -- "$dev_exe" >/dev/null; }

# Quits the release and Dev copies and waits until they're gone.
quit_all() {
  pkill -f -- "$release_exe" 2>/dev/null
  pkill -f -- "$dev_exe" 2>/dev/null
  for _ in $(seq 1 50); do
    running || return 0
    sleep 0.1
  done
  fail "couldn't quit the running app"
}

# Prints the timestamp of the newest log entry matching a predicate, as seconds since
# midnight with microseconds, or nothing if there's none yet.
log_seconds() {
  log show --last 1m --style ndjson --predicate "$1" 2>/dev/null | awk '
    match($0, /"timestamp":"[0-9-]+ [0-9:.]+/) {
      split(substr($0, RSTART + 13, RLENGTH - 13), parts, " ")
      split(parts[2], hms, ":")
      # The time zone offset is dropped; a daylight-saving change mid-run would be off by
      # an hour, which the midnight check below does not catch. Rare enough to accept.
      t = hms[1] * 3600 + hms[2] * 60 + hms[3]
    }
    END { if (t != "") printf "%.6f\n", t }'
}

# Waits up to 10 s for a log entry and prints its time.
wait_for_log() {
  local t
  for _ in $(seq 1 40); do
    t=$(log_seconds "$1")
    [ -n "$t" ] && { echo "$t"; return 0; }
    sleep 0.25
  done
  return 1
}

echo "Measuring launch to menu bar icon ($runs runs)"
launches=()
for i in $(seq 1 "$runs"); do
  quit_all
  sleep 2
  marker="perf-launch-$$-$i-$RANDOM"
  logger "$marker"
  open "$app" || fail "couldn't open $app"
  # Let the launch run before polling: each poll starts `log show`, which costs CPU.
  sleep 0.5
  start=$(wait_for_log "eventMessage == \"$marker\"") || fail "the start marker never reached the log"
  launched="subsystem == \"$bundle_id\" AND eventMessage BEGINSWITH \"Launched\""
  end=""
  for _ in $(seq 1 40); do
    end=$(log_seconds "$launched")
    # Ignore the previous run's line; the newest one must come after this run's marker.
    [ -n "$end" ] && awk -v s="$start" -v e="$end" 'BEGIN { d = e - s; if (d < -43200) d += 86400; exit !(d > 0) }' && break
    end=""
    sleep 0.25
  done
  [ -n "$end" ] || fail "the app's launch line never appeared (is it still logging at notice level?)"
  ms=$(awk -v s="$start" -v e="$end" 'BEGIN { d = e - s; if (d < -43200) d += 86400; printf "%.0f", d * 1000 }')
  echo "  run $i: $ms ms"
  launches+=("$ms")
done
sorted=$(printf '%s\n' "${launches[@]}" | sort -n)
# The middle value, or the mean of the two middle values for an even number of runs.
median=$(printf '%s\n' "$sorted" | awk -v n="$runs" '
  { v[NR] = $1 }
  END { if (n % 2) print v[(n + 1) / 2]; else printf "%.0f\n", (v[n / 2] + v[n / 2 + 1]) / 2 }')
low=$(printf '%s\n' "$sorted" | head -1)
high=$(printf '%s\n' "$sorted" | tail -1)

echo "Measuring idle footprint ($idle s after launch)"
quit_all
sleep 2
open "$app" || fail "couldn't open $app"
sleep "$idle"
pid=$(pgrep -f -- "$release_exe" | head -1)
[ -n "$pid" ] || fail "the app isn't running"
footprint_line=$(footprint "$pid" 2>/dev/null | grep -m1 -o 'Footprint: [0-9.]* [KMG]B')
[ -n "$footprint_line" ] || fail "couldn't read the footprint of pid $pid"
footprint=${footprint_line#Footprint: }
quit_all

date=$(date +%Y-%m-%d)
model=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ { m = $2 } /Chip|Processor Name/ { c = $2 } END { printf "%s, %s", m, c }')
mac="$model ($(sysctl -n hw.model)), macOS $(sw_vers -productVersion)"
xcode=$(xcodebuild -version | head -1)
method="Release build, $xcode, \`make perf\` (\`scripts/measure-baseline.sh\`)"

rows="| $milestone | $date | $mac | NFR-2 | $footprint physical footprint | $method: \`footprint\` $idle s after launch, menu closed. Target < 40 MB. |
| $milestone | $date | $mac | NFR-4 | $median ms launch to menu bar icon (median of $runs; ${low}–${high} ms) | $method: from a log marker just before \`open\` to the app's \"Launched: status item installed\" line (the icon is drawn a run-loop pass later), 2 s between runs, caches warm. Target < 0.5 s. |"

mkdir -p .build/perf
printf '%s\n' "$rows" >.build/perf/latest.md

echo
echo "Launch: median $median ms (${low}–${high} ms over $runs runs). Idle footprint: $footprint."
echo "Rows for docs/perf.md are in .build/perf/latest.md."
if [ "$record" -eq 1 ]; then
  printf '%s\n' "$rows" >>docs/perf.md
  echo "Appended them to docs/perf.md."
fi
