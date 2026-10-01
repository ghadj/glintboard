#!/bin/bash
# First-time setup for contributors. Safe to run again.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

echo "Checking your setup"

[ "$(uname)" = "Darwin" ] || fail "This project builds a macOS app and needs a Mac."

xcodebuild -version >/dev/null 2>&1 || fail "Xcode not found. Install it from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
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
if swift test --package-path Packages/ScrapKit --parallel >/tmp/scrapkit-tests.log 2>&1; then
  ok "Core tests pass"
else
  tail -n 30 /tmp/scrapkit-tests.log
  fail "Core tests failed (full log: /tmp/scrapkit-tests.log)"
fi

echo
echo "Ready. Next: 'make run' to launch the Dev app, or open App.xcodeproj in Xcode."
