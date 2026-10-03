# 0010: Brand-neutral code, modules, bundle identifier, and data folder; the product name lives only in Branding.xcconfig

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M0-R1, M0-R11, M0-R12, M1-R5

## Context

The product name may change before or after release. Renaming should not touch code, data, or the permissions users have granted.

## Decision

- The product name lives only in `Config/Branding.xcconfig` (`APP_DISPLAY_NAME`), the app icon, and user-facing docs. Code reads it at runtime through `AppInfo.displayName` and never contains it as a literal; String Catalog entries use a placeholder for it.
- Code and modules use neutral names: the target and scheme are `App`, and the package uses the domain word "Scrap" (`ScrapKit`: `ScrapModel`, `ScrapStorage`, `ScrapCapture`, `ScrapTestSupport`).
- The bundle identifier is `io.github.ghadj.glintboard` (matching today's name by choice). It, the default data folder (`~/Library/Application Support/<bundle id>/Library`), and the log subsystem never change, even if the app is renamed.
- Debug builds append `.dev` to the bundle identifier and "Dev" to the display name, so a contributor's build never shares data, preferences, or permissions with an installed release.

## Consequences

- `scripts/check-branding.sh` fails CI if the name appears in `App/`, `AppTests/`, `App.xcodeproj` (apart from Xcode's own product file names), or `Packages/`; `scripts/test-checks.sh` proves it does.
- There is no `InfoPlist.xcstrings` for now, because Xcode copies the product name into it on IDE builds (see "Naming and branding" in `docs/architecture.md`).
- Changing `APP_BUNDLE_ID` or the default data folder is on the "ask first" list in `AGENTS.md`.
