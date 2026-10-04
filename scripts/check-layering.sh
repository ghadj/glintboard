#!/bin/bash
# Fails if a ScrapKit target imports a module outside its layer. The compiler only catches
# this on clean builds: once a sibling module has been built, an incremental build accepts
# an import the target doesn't depend on (spike S0-1, docs/plans/M0.md).
#
# Usage: scripts/check-layering.sh [root]
# root defaults to the repository root. Exits 1 on a violation, 2 if root doesn't exist.
set -uo pipefail
root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
src="$root/Packages/ScrapKit/Sources"
[ -d "$root" ] || {
  echo "error: $root is not a directory"
  exit 2
}

# Imports each target may use, besides Swift itself. Keep in step with the target
# dependencies in Package.swift and "Module structure" in docs/architecture.md.
# CryptoKit: SHA-256 fingerprints (Model) and the recent-write ledger (Storage).
# CoreServices: the FSEvents watcher (Storage).
# Synchronization: Mutex in test fakes such as FakeWallClock (Test support; M1 plan Q16b).
allowed() {
  case "$1" in
    ScrapModel) echo "Foundation CryptoKit" ;;
    ScrapStorage) echo "Foundation CryptoKit os SQLite3 CoreServices ScrapModel" ;;
    ScrapCapture) echo "Foundation os ScrapModel ScrapStorage" ;;
    ScrapTestSupport) echo "Foundation CryptoKit os Synchronization ScrapModel ScrapStorage ScrapCapture" ;;
    *) return 1 ;;
  esac
}

# An import declaration: optional attributes (@testable, @preconcurrency, ...), an optional
# access level, an optional declaration kind (import struct M.T), then the module name.
attrs='([[:space:]]*@[A-Za-z_]+([(][^)]*[)])?)*'
access='([[:space:]]*(public|package|internal|fileprivate|private))?'
kind='([[:space:]]+(typealias|struct|class|enum|protocol|let|var|func))?'
import_re="^${attrs}${access}[[:space:]]*import${kind}[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)"

[ -d "$src" ] || {
  echo "layering check passed (no package sources)"
  exit 0
}

fail=0
for dir in "$src"/*/; do
  [ -d "$dir" ] || continue
  target=$(basename "$dir")
  if ! list=$(allowed "$target"); then
    echo "error: no layering rule for target $target; add one to scripts/check-layering.sh"
    fail=1
    continue
  fi
  while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    line=${rest%%:*}
    text=${rest#*:}
    [[ $text =~ $import_re ]] || continue
    module=${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
    [ "$module" = Swift ] && continue
    case " $list " in
      *" $module "*) ;;
      *)
        echo "error: $target imports $module (${file#"$root"/}:$line); allowed: $list"
        fail=1
        ;;
    esac
  done < <(grep -rnE --include='*.swift' "$import_re" "$dir")
done

[ "$fail" -eq 0 ] && echo "layering check passed"
exit "$fail"
