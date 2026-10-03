# 0001: Native only: Apple frameworks, no third-party packages or build tools

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M0-R5, M0-R7, M0-R12

## Context

Native only is one of the architecture's drivers: Apple frameworks only, with small in-house implementations where Foundation stops (`docs/architecture.md`, "Purpose and drivers"). The app size budget (< 15 MB) relies on native Swift with no third-party dependencies (`docs/design.md`, "Resource budget"). The app also needs Xcode on macOS, which containers can't provide, so Xcode is the whole toolchain for contributors.

## Decision

The app and its build use Swift and Apple frameworks only. No Swift packages, vendored code, or extra build tools.

- System SQLite3 through its C API instead of GRDB.
- Xcode synchronized folders and `Config/*.xcconfig` files instead of XcodeGen.
- A small in-house YAML-subset codec for frontmatter instead of a YAML library.
- Contributor setup needs only the Xcode in `.xcode-version`: no dev container, Homebrew packages, or version managers. The `Makefile` is the single entry point (`make bootstrap`, `make check`, `make ci`), Debug builds are a separate Dev app, and agent rules live in agent-neutral `AGENTS.md`.

## Consequences

- `scripts/check-native-only.sh` fails CI on any package dependency, remote `Package.resolved`, or remote package reference; `scripts/test-checks.sh` proves it does (M0-R7).
- Some code that a library would provide (the codec, SQLite bindings) is written and tested in-house, with fixtures.
- Adding any third-party package, tool, or vendored code is on the "ask first" list in `AGENTS.md`.
