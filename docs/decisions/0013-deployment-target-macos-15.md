# 0013: Deployment target macOS 15

- **Date:** 2026-10-03
- **Status:** accepted
- **Requirements:** M0-R1

## Context

The design and M0-R1 set the minimum macOS to 14 (Sonoma), for current SwiftUI and ScreenCaptureKit APIs and the actor executor on a `DispatchSerialQueue`. The project as created set `MACOSX_DEPLOYMENT_TARGET = 15.0` in `Config/Base.xcconfig` and `.macOS(.v15)` in `Packages/ScrapKit/Package.swift`. The project is built with Xcode 27.

Raising the target needs the project owner's approval (`AGENTS.md`). The owner chose 15 on 2026-10-03, during M0 planning. Why 15 is reasonable:
- Nothing the design needs is available only on 14. The `DispatchSerialQueue` actor executor, ScreenCaptureKit and current SwiftUI all work on 15.
- The build and CI never run on macOS 14 (local Macs and the `xcode-27` runner are newer), so a 14 target would be supported in name only.
- Keeping 15 avoids churn: the build settings and the package already use it.

## Decision

The minimum macOS is 15 (Sequoia), for both the app and the package.

## Consequences

- Everything the design relies on from macOS 14 is still available.
- Contributors and users on macOS 14 can't run the app. That's acceptable for a 0.1 release in late 2026.
- `docs/design.md` ("Privacy, permissions, and distribution" and "Open questions") and the M0-R1 text in `docs/milestones.md` now say macOS 15.
- AI assist via Foundation Models still needs macOS 26 and hides where unavailable, as before.
