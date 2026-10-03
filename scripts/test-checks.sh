#!/bin/bash
# Self-test for the check scripts: each must pass on a clean copy of the tree and fail on a
# seeded violation. Runs in `make check`, so a check that quietly stops catching things
# fails CI instead of letting violations through. Covers the layering (M0-R2),
# native-only, and branding (M0-R7) checks.
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

# Native-only and branding (M0-R7) run on a copy of the project, package, and branding config.
fresh_project() {
  fresh
  cp Packages/ScrapKit/Package.swift "$root/Packages/ScrapKit/"
  cp -R App AppTests App.xcodeproj "$root/"
  rm -rf "$root/App.xcodeproj/xcuserdata" "$root/App.xcodeproj/project.xcworkspace/xcuserdata"
  mkdir -p "$root/Config"
  cp Config/Branding.xcconfig "$root/Config/"
}
pbxproj="App.xcodeproj/project.pbxproj"
# insert_in_project <line>: adds a line inside the project's objects dictionary.
insert_in_project() {
  awk -v line="$1" '{ print } /^[[:space:]]*objects = \{/ { print line }' \
    "$root/$pbxproj" >"$work/pbx" && mv "$work/pbx" "$root/$pbxproj"
  # Without this, a changed project format would make the "passes" cases pass vacuously.
  grep -qF -- "$1" "$root/$pbxproj" || {
    echo "error: self-test couldn't insert into $pbxproj (no 'objects = {' line?)"
    exit 2
  }
}
# Read, not written here, so a rename stays a one-line change in Branding.xcconfig.
name=$(sed -n 's/^[[:space:]]*APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' Config/Branding.xcconfig | head -1 | sed 's/[[:space:]]*$//')
lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

fresh_project
expect pass native_only_clean_tree_passes scripts/check-native-only.sh "$root"

fresh_project
# BSD sed (macOS and the CI runner): `-i ''` and a backslash-newline in the replacement.
sed -i '' 's|^\([[:space:]]*\)platforms:|\1dependencies: [.package(url: "https://github.com/example/example", from: "1.0.0")],\
\1platforms:|' "$root/Packages/ScrapKit/Package.swift"
expect fail native_only_package_dependency_fails scripts/check-native-only.sh "$root"

fresh_project
mkdir -p "$root/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
printf '{"pins":[{"identity":"example","kind":"remoteSourceControl","location":"https://github.com/example/example","state":{"version":"1.0.0"}}],"version":3}\n' \
  >"$root/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
expect fail native_only_package_resolved_fails scripts/check-native-only.sh "$root"

fresh_project
insert_in_project '		AA0000000000000000000001 /* XCRemoteSwiftPackageReference "example" */ = {isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/example/example";};'
expect fail native_only_remote_reference_fails scripts/check-native-only.sh "$root"

fresh_project
insert_in_project '		AA0000000000000000000002 /* XCLocalSwiftPackageReference "Packages/ScrapKit" */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/ScrapKit;};'
expect pass native_only_local_reference_passes scripts/check-native-only.sh "$root"

fresh_project
expect pass branding_clean_tree_passes scripts/check-branding.sh "$root"

fresh_project
printf 'let title = "%s"\n' "$name" >"$root/App/SelfTestProbe.swift"
expect fail branding_name_in_swift_fails scripts/check-branding.sh "$root"

fresh_project
printf '// %s\n' "$lower_name" >"$root/Packages/ScrapKit/Sources/ScrapModel/SelfTestProbe.swift"
expect fail branding_lowercase_name_in_package_fails scripts/check-branding.sh "$root"

fresh_project
insert_in_project "		AA0000000000000000000003 /* $name Dev.app */ = {isa = PBXFileReference; path = \"$name Dev.app\";};"
expect pass branding_xcode_product_name_passes scripts/check-branding.sh "$root"

fresh_project
insert_in_project "		AA0000000000000000000004 = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = $name;};};"
expect fail branding_name_in_project_setting_fails scripts/check-branding.sh "$root"

if [ "$failures" -eq 0 ]; then
  echo "check self-test passed"
else
  echo "error: $failures check self-test case(s) failed"
fi
exit $((failures > 0))
