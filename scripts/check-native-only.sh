#!/bin/bash
# Fails if any third-party Swift package is declared, resolved, or referenced.
# Local packages (Packages/ScrapKit) are fine.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
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
