# 0004: Reference health lives in the index; background work never writes scrap files

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M1-R9, M4-R11, M4-R12, M4-R13, M4-R14

## Context

Every scrap keeps a live reference to its source, and the app checks whether that source changed, moved, or disappeared. Data safety, the first architecture driver, rules out rewrites of user files by background work (`docs/architecture.md`, "Purpose and drivers"), and health checks are background work.

## Decision

- Frontmatter holds capture facts and user edits only. Reference health (`status`, `lastChecked`) lives in the index's `health` table. Health checks never write scrap files.
- Statuses are `ok`, `changed`, `trashed`, `missing`, and `unknown`. A file bookmark that resolves inside the Trash is `trashed`; one that can't resolve is `missing`; one that resolves to a new path refreshes the stored path and stays `ok`.
- Unavailable sources: trashed and missing scraps are never removed automatically. They stay with their snapshot until the user runs Clear Unavailable (with a confirmation), which moves them to the app's own trash.
- Checks run only on events: local file references when a card is visible (at most once a minute), Mail references at most every 24 hours and only while Mail is already running, plus on demand.

## Consequences

- Health is lost when the index is rebuilt and simply re-checked; that's acceptable because it's derived.
- No timers: checks follow visibility and user actions, keeping idle CPU at zero.
