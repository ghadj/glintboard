#!/bin/bash
# Self-test for the check scripts: each must pass on a clean copy of the tree and fail on a
# seeded violation. Runs in `make check`, so a check that quietly stops catching things
# fails CI instead of letting violations through. Covers the layering check (M0-R2);
# M0-R7 adds the native-only and branding checks.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

work=$(mktemp -d "${TMPDIR:-/tmp}/check-selftest.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
failures=0

# A fresh copy of the package sources (not build output) at $root.
root="$work/root"
fresh() {
  rm -rf "$root"
  mkdir -p "$root/Packages/ScrapKit"
  cp -R Packages/ScrapKit/Sources "$root/Packages/ScrapKit/"
}

# expect pass|fail <case name> <command...>
# "fail" means the check reported a violation (exit 1). Any other status (a crash, a missing
# script) counts as broken, so a check that can't run never looks like one that caught something.
expect() {
  local want=$1 name=$2 got status
  shift 2
  "$@" >"$work/out" 2>&1
  status=$?
  case $status in
    0) got=pass ;;
    1) got=fail ;;
    *) got="broken (exit $status)" ;;
  esac
  if [ "$got" = "$want" ]; then
    echo "  ok    $name"
  else
    echo "  FAIL  $name (expected $want, got $got)"
    sed 's/^/        /' "$work/out"
    failures=$((failures + 1))
  fi
}

# add_file <target> <line>: adds a source file containing <line> to a target in the copy.
add_file() {
  mkdir -p "$root/Packages/ScrapKit/Sources/$1"
  printf '%s\n' "$2" >"$root/Packages/ScrapKit/Sources/$1/SelfTestProbe.swift"
}

echo "check self-test"

# Layering (M0-R2, spike S0-1)
fresh
expect pass layering_clean_tree_passes scripts/check-layering.sh "$root"

fresh && add_file ScrapModel 'import ScrapStorage'
expect fail layering_model_imports_storage_fails scripts/check-layering.sh "$root"

fresh && add_file ScrapModel 'import AppKit'
expect fail layering_model_imports_appkit_fails scripts/check-layering.sh "$root"

fresh && add_file ScrapCapture 'import SQLite3'
expect fail layering_capture_imports_sqlite_fails scripts/check-layering.sh "$root"

fresh && add_file ScrapModel '@preconcurrency internal import ScrapStorage'
expect fail layering_attributed_import_fails scripts/check-layering.sh "$root"

fresh && add_file ScrapModel 'import struct ScrapStorage.SQLiteLibrary'
expect fail layering_scoped_import_fails scripts/check-layering.sh "$root"

fresh && add_file ScrapModel '// import ScrapStorage'
expect pass layering_commented_import_passes scripts/check-layering.sh "$root"

fresh && add_file ScrapModel 'import CryptoKit'
expect pass layering_model_imports_cryptokit_passes scripts/check-layering.sh "$root"

fresh && add_file ScrapStorage 'import ScrapModel'
expect pass layering_storage_imports_model_passes scripts/check-layering.sh "$root"

fresh && add_file ScrapUnlisted 'import Foundation'
expect fail layering_unlisted_target_fails scripts/check-layering.sh "$root"

if [ "$failures" -eq 0 ]; then
  echo "check self-test passed"
else
  echo "error: $failures check self-test case(s) failed"
fi
exit $((failures > 0))
