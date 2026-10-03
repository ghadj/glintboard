# 0009: Composition root with initializer injection; no singletons

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M0-R9, M0-R11

## Context

Tests and previews need to swap every system client and service for a fake. Singletons and global service locators make that hard and hide dependencies.

## Decision

`AppEnvironment` (main actor) is the composition root. It's created in `applicationDidFinishLaunching` and builds the store, index, coordinator, system clients, settings, and controllers, handing them down through initializers. Nothing else creates services, and there are no singletons; tests and previews build their own pieces with fakes.

**Exemption (2026-10-03, from the M0-R11 review):** immutable per-process constants are not services and may be static: `AppInfo.main` (the display name and bundle id from Info.plist), the static `os.Logger`s, and the `OSSignposter`s. Controllers whose output depends on the name still take an `AppInfo` through their initializer, so tests can pass their own.

## Consequences

- Every new service is added to `AppEnvironment` and injected; reaching for a static or a shared instance needs a reason that fits the exemption.
