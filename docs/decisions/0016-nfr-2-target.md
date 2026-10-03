# 0016: NFR-2 target confirmed at < 40 MB after the M0 baseline

- **Date:** 2026-10-03
- **Status:** accepted
- **Requirements:** M0-R10

## Context

NFR-2 sets the memory budget with the shelf closed at < 40 MB, to be confirmed or adjusted after the M0 baseline ("Open decisions" in `docs/milestones.md`). M0-R10 says to revisit NFR-2 before M1 if the empty app's idle footprint exceeds 30 MB; the architecture lists "idle memory target too tight for a SwiftUI host" as a risk with that early signal.

The M0 baseline (`docs/perf.md`, from `make perf`): the empty menu bar app, a Release build with only the status item and its menu, has a physical footprint of 12 MB a minute after launch. An earlier hand measurement the same day gave 17 MB; footprint varies a few MB between launches. Both were taken on a MacBook Air with an Apple M3 (Mac15,12) and macOS 27.0.1, not the M1 MacBook Air the NFRs name; the footprint depends little on the chip.

## Decision

NFR-2 stays at < 40 MB with the shelf closed. Both measurements are well under the 30 MB threshold, so no revisit is needed before M1.

## Consequences

- M1 has roughly 23–28 MB of headroom for the store, the index, and the shelf's closed state. The architecture's mechanisms (releasing the hosting view, card models, and thumbnail cache when the shelf closes) are what keep it there.
- NFR-2 is measured again at the end of M1 ("NFR-1, NFR-2, NFR-4 measured and recorded") with `make perf`, and re-checked on an M1 MacBook Air if one becomes available. If it approaches 40 MB, "load SwiftUI only when the shelf opens" is the planned mitigation.
