#!/bin/bash
# Fails if the product's display name appears in code or project files outside
# Config/Branding.xcconfig. Keeps a future rename to a one-line change.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

cfg=Config/Branding.xcconfig
if [ ! -f "$cfg" ]; then echo "branding check skipped: $cfg not found"; exit 0; fi

name=$(sed -n 's/^[[:space:]]*APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' "$cfg" | head -1 | sed 's/[[:space:]]*$//')
if [ -z "$name" ]; then echo "error: APP_DISPLAY_NAME is not set in $cfg"; exit 1; fi

paths=()
for p in App AppTests App.xcodeproj Packages; do [ -e "$p" ] && paths+=("$p"); done
[ ${#paths[@]} -eq 0 ] && { echo "branding check passed (nothing to scan yet)"; exit 0; }

hits=$(grep -rIni --exclude-dir=.build --exclude-dir=xcuserdata -- "$name" "${paths[@]}" 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "error: product name \"$name\" found outside $cfg:"
  echo "$hits"
  exit 1
fi
echo "branding check passed"
