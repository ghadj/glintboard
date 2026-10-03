#!/bin/bash
# First-time setup for contributors. Safe to run again.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

echo "Checking your setup"

[ "$(uname)" = "Darwin" ] || fail "This project builds a macOS app and needs a Mac."

# The developer directory must be an Xcode app, not the Command Line Tools. xcode-select
# works before the license is accepted; xcodebuild doesn't, so it waits until after.
dev=$(xcode-select -p 2>/dev/null || true)
case "$dev" in
  *.app/Contents/Developer) ;;
  *) fail "Xcode not found or not selected (developer directory: ${dev:-none}). Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" ;;
esac

# A fresh Xcode install needs its license accepted and its first-launch components
# installed before swift and xcodebuild can build anything.
if xcodebuild -license check >/dev/null 2>&1; then
  ok "Xcode license accepted"
else
  fail "Xcode's license hasn't been accepted. Run: sudo xcodebuild -license accept"
fi
if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  ok "Xcode first-launch setup done"
else
  fail "Xcode's first-launch setup hasn't run. Run: sudo xcodebuild -runFirstLaunch (or open Xcode once)"
fi

have=$(xcodebuild -version | awk 'NR==1 {print $2}')
want=$(cat .xcode-version 2>/dev/null || echo "")
have_mm=$(echo "$have" | cut -d. -f1,2); want_mm=$(echo "$want" | cut -d. -f1,2)
if [ -n "$want" ] && [ "$have_mm" != "$want_mm" ]; then
  warn "Xcode $have found; the project uses $want (see .xcode-version). Other versions usually work but CI uses $want."
else
  ok "Xcode $have"
fi

xcrun --find swift-format >/dev/null 2>&1 && ok "swift-format (bundled with Xcode)" || warn "swift-format not found; formatting checks will be skipped locally"

if [ ! -f Config/Local.xcconfig ]; then
  cp Config/Local.xcconfig.example Config/Local.xcconfig
  warn "Created Config/Local.xcconfig. Add your Team ID there so macOS remembers permissions between builds (optional)."
else
  ok "Config/Local.xcconfig exists"
fi

echo "Running core tests"
# Build output, including this log, stays in .build/ (gitignored).
log=.build/bootstrap-core-tests.log
mkdir -p .build
# SWIFT_TEST_FLAGS as for make test-core, e.g. --disable-sandbox inside an outer sandbox.
if swift test --package-path Packages/ScrapKit --parallel ${SWIFT_TEST_FLAGS:-} >"$log" 2>&1; then
  ok "Core tests pass"
else
  tail -n 30 "$log"
  fail "Core tests failed (full log: $log)"
fi

echo
echo "Ready. Next: 'make run' to launch the Dev app, or open App.xcodeproj in Xcode."
