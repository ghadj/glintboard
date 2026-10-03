#!/bin/bash
# Fails if the product's display name appears in code or project files outside
# Config/Branding.xcconfig. Keeps a future rename to a one-line change.
#
# One exception: inside App.xcodeproj, Xcode itself writes the built product's
# file name ("<name>.app", "<name> Dev.app") into the product reference and the
# schemes' BuildableName, derived from Branding.xcconfig. Xcode rewrites those on
# a rename, so they're ignored. The name anywhere else still fails.
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

# Drop Xcode-generated product file names in the project, then keep only lines
# that still mention the name.
if [ -n "$hits" ]; then
  # ENVIRON avoids awk's escape processing of -v values.
  hits=$(printf '%s\n' "$hits" | BRAND_NAME="$name" \
    BRAND_RE="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[][\.*^$+?(){}|/]/\\&/g')" awk '
    BEGIN { name = tolower(ENVIRON["BRAND_NAME"]); re = ENVIRON["BRAND_RE"] "( dev)?\\.app" }
    {
      line = tolower($0)
      if (index(line, "app.xcodeproj/") == 1) gsub(re, "", line)
      if (index(line, name) > 0) print $0
    }')
fi

if [ -n "$hits" ]; then
  echo "error: product name \"$name\" found outside $cfg:"
  echo "$hits"
  exit 1
fi
echo "branding check passed"
