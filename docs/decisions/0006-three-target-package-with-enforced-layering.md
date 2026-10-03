# 0006: Three-target package with enforced layering and a test-support target

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M0-R2

## Context

Most of the app's logic (codec, store, index, capture pipeline, providers) should be testable in seconds without AppKit, permissions, or the real system apps. Conventions alone erode; the layering should be checked by tools.

## Decision

`Packages/ScrapKit` has three library targets with one-way dependencies, plus a fakes target:

- `ScrapModel`: value types, codec, fingerprints, ranks, layout math. Imports only Foundation and CryptoKit.
- `ScrapStorage`: file store, folder watcher, SQLite index, reconciliation. Depends on Model.
- `ScrapCapture`: pipeline, privacy filter, providers, system-client protocols. Depends on Model and Storage.
- `ScrapTestSupport`: fakes for every system client and fixture loaders, linked only by test targets.

Nothing below the app imports AppKit, SwiftUI, or ApplicationServices; Core reaches the system only through protocols the app implements.

**Enforcement** (added 2026-10-03). Spike S0-1 (Xcode 27) showed target dependencies alone aren't enough: a deliberate `import ScrapStorage` in `ScrapModel` fails a clean build ("unable to resolve module dependency") but builds fine incrementally once `ScrapStorage` has been built. So `scripts/check-layering.sh` checks every library target's imports against an allowed list in `make check`, and `scripts/test-checks.sh` proves it catches violations.

## Consequences

- CI builds clean and runs `make check`, so violations fail CI; locally, `make check` catches them without a clean build.
- A new target or a new framework import needs a one-line change to the allowed list in `check-layering.sh`, which shows up in review.
- Whether `xcodebuild` builds enforce target dependencies the same way is untested until M1 links ScrapKit into the app.
