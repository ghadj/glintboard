#!/bin/bash
# Fails if any third-party Swift package is declared, resolved, or referenced.
# Local packages (Packages/ScrapKit) are fine.
#
# Usage: scripts/check-native-only.sh [root]
# root defaults to the repository root; scripts/test-checks.sh passes a scratch copy
# with seeded violations. Exits 1 on a violation, 2 if root doesn't exist.
set -uo pipefail
cd "${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || exit 2
fail=0

# 1. Resolved remote packages
while IFS= read -r f; do
  if grep -q '"location"' "$f"; then
    echo "error: remote packages resolved in $f"; fail=1
  fi
done < <(find . -name Package.resolved -not -path '*/.build/*' -not -path '*/DerivedData/*' 2>/dev/null)

# 2. Package dependencies declared in any manifest
while IFS= read -r f; do
  if grep -nE '\.package[[:space:]]*\(' "$f"; then
    echo "error: package dependency declared in $f"; fail=1
  fi
done < <(find . -name Package.swift -not -path '*/.build/*' 2>/dev/null)

# 3. Remote package references in the Xcode project
if [ -f App.xcodeproj/project.pbxproj ] && grep -q 'XCRemoteSwiftPackageReference' App.xcodeproj/project.pbxproj; then
  echo "error: remote Swift package referenced in App.xcodeproj"; fail=1
fi

[ "$fail" -eq 0 ] && echo "native-only check passed"
exit "$fail"
