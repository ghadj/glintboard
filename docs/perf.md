# Performance log

Measurements per milestone, taken on a Release build with the seed libraries. See "Non-functional requirements" in `milestones.md` for targets and methods. `make perf PERF_FLAGS="--milestone Mx --record"` measures NFR-2 and NFR-4 and appends the rows here; run it in Terminal, outside Claude Code's sandbox.

| Milestone | Date | Mac | NFR | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| M0 | 2026-10-03 | MacBook Air, Apple M3 (Mac15,12), macOS 27.0.1 | NFR-2 | 12 MB physical footprint | Release build, Xcode 27.0, `make perf` (`scripts/measure-baseline.sh`): `footprint` 60 s after launch, menu closed. Target < 40 MB. |
| M0 | 2026-10-03 | MacBook Air, Apple M3 (Mac15,12), macOS 27.0.1 | NFR-4 | 159 ms launch to menu bar icon (median of 5; 146–161 ms) | Release build, Xcode 27.0, `make perf` (`scripts/measure-baseline.sh`): from a log marker just before `open` to the app's "Launched: status item installed" line (the icon is drawn a run-loop pass later), 2 s between runs, caches warm. Target < 0.5 s. |
