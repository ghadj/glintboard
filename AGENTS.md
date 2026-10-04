# Glintboard: guide for coding agents and contributors

This file is read by AI coding agents (Claude Code imports it from `CLAUDE.md`; other agents read `AGENTS.md` directly) and is a useful summary for human contributors too. `CONTRIBUTING.md` covers setup and the pull request process.


Glintboard is a lightweight, open source macOS shelf and mood board: a clipboard that remembers where everything came from. Every scrap keeps a live reference to its source (Safari page, Mail message, file, screenshot), can carry a note, and is stored as a plain Markdown file. Native only: Swift and Apple frameworks, no third-party packages.

## Read these first

- `docs/design.md`: behavior, data model, UI spec, resource budget. Source of truth for what the app does.
- `docs/architecture.md`: module structure, key types, concurrency model, persistence, flows, failure modes. Source of truth for how it's built.
- `docs/milestones.md`: requirement IDs (`M2-R6`), tracks (Core/App), acceptance criteria. Work one requirement at a time.
- `docs/plans/<milestone>.md`: the approved plan for the current milestone. Follow it; if it's wrong, say so instead of deviating silently.
- `docs/decisions/`: decisions and spike outcomes. Check before re-deciding anything.

## Commands

Use the Makefile; it wraps everything and needs only Xcode. `make help` lists targets.

```bash
make bootstrap   # first-time setup and core tests
make test-core   # fast package tests; run constantly
make test        # core and app tests
make build       # build the Debug ("Dev") app
make run         # build and launch the Dev app
make format      # fix formatting
make check       # lint, native-only, branding, and layering checks
make perf        # Release baseline: idle footprint and launch time (run in Terminal)
make ci          # everything CI runs
```

Build output stays in `.build/`. Build, test, check, bootstrap, and perf runs also save their output to `.build/logs/<target>.log` and a summary to `.build/logs/summary.md`, so results of a run in Terminal can be read afterwards; the same summary is printed at the end of the run. Debug builds are a separate "Dev" app (bundle id ending in `.dev`) with their own data folder and permissions, so they never touch an installed release. CI builds ad-hoc signed (`XCB_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="`), because Apple silicon won't run unsigned code; locally, put your Team ID in `Config/Local.xcconfig` so permissions survive rebuilds.

## Architecture

`Packages/ScrapKit` has three library targets plus `ScrapTestSupport`; target dependencies and `scripts/check-layering.sh` enforce the layering (the compiler alone only catches violations on clean builds). Details in `docs/architecture.md`.

- `ScrapModel` (Foundation and CryptoKit only): value types, YAML-subset frontmatter codec, fingerprints, fractional `Rank`, text-fragment builder, masonry layout math, and the `WallClock` protocol (here so the store can take one too).
- `ScrapStorage` (Model + SQLite3): file store actor (atomic writes, FSEvents watcher with self-echo suppression), index actor (SQLite3 C API, FTS5 with FTS4 fallback, reference health), launch reconciliation. The store uses real files; its tests use temporary folders.
- `ScrapCapture` (Model + Store): capture pipeline, privacy filter, `ProvenanceProvider` protocol, registry, providers' logic written against system-client protocols (`AppleEventClient`, `AccessibilityClient`, `PasteboardClient`, `WorkspaceClient`, `ThumbnailClient`). Fakes live in the `ScrapTestSupport` target.
- `App/`: composition root (`AppEnvironment`, no singletons), AppKit shell (menu bar, `NSPanel` shelf, board window with `NSCollectionView`), SwiftUI views inside, and the real system clients. Keep it thin.

## Architecture rules (from the design review)

1. Markdown files are the source of truth; the index is a disposable cache.
2. A collection is a folder. Scrap files never store their collection.
3. Frontmatter holds capture facts and user edits only. Reference health (`status`, `lastChecked`) lives in the index; health checks never write scrap files.
4. The `id` in frontmatter is authoritative; never parse ids from file names.
5. The frontmatter writer always double-quotes strings and preserves unknown keys.
6. Board order is a fractional `Rank`; a reorder writes exactly one file.
7. Files are referenced (path + bookmark + thumbnail), never copied. Images over 20 MB are stored downscaled.
8. Every Apple Event and Accessibility call has an explicit short timeout (about 250 ms) and runs on the dedicated system-client actor (its own serial queue), never the main actor or the cooperative pool.
9. Capture context is taken at trigger time from the last external frontmost app, before any Glintboard UI appears.
10. The synthetic ⌘C and paste-back paths skip when secure event input is on, and restored clipboards are marked transient.
11. The store ignores FSEvents echoes of its own writes.
12. Brand-neutral code: never write the product name in Swift, project files, or module names. Use `AppInfo.displayName` for user-facing text; the name lives only in `Config/Branding.xcconfig`. Modules use the domain word "Scrap" (`ScrapKit`, `ScrapModel`, ...); logs use the bundle identifier.

## Non-negotiables

- Resource budget: zero idle CPU by default, no polling loops, every timer has a tolerance and a stated reason.
- No blocking work on the main actor. Providers are `Sendable` and respect the 300 ms budget.
- Every source goes through `ProvenanceProvider`; no special cases in the pipeline.
- Privacy: never store concealed or transient pasteboard items; respect the exclusion list; no network calls except opt-in web checks; log captured content only as `privacy: .private`.
- Native only: Apple frameworks only. No Swift packages, vendored code, or extra build tools.
- Every user-facing string goes in `Localizable.xcstrings`.

## Workflow rules

- One requirement per commit: `M2-R6: short summary`.
- Core requirements: write failing tests for the automated acceptance criteria first (Swift Testing), then implement.
- Run `make test-core` before saying a requirement is done.
- The Xcode project uses synchronized folders, so new files need no project edits. Build settings live in `Config/*.xcconfig`. For new targets or build phases, ask me to do it in Xcode.
- Behavior that differs from `docs/design.md` needs a design doc update and a decision note (`/decision`) in the same commit.
- When two sessions run in parallel, Core work and App work stay in separate worktrees and touch separate directories.
- After building in the Xcode app, run `git status` before committing. Xcode rewrites some files on its own: it updates the product file name in `project.pbxproj` when `APP_DISPLAY_NAME` changes, and adds Info.plist keys (with the product name) to any `InfoPlist.xcstrings`. Revert what you didn't mean to change.

## Ask before doing any of these

- Silencing concurrency errors with `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or blanket `@MainActor`. Explain the error and propose a design fix instead.
- Changing the shelf panel's activation, key-window, or focus behavior.
- Touching signing, entitlements, `Info.plist` privacy strings, keychain access, or `Config/*.xcconfig`.
- Adding a timer, background task, or anything that runs while idle.
- Adding any third-party package, tool, or vendored code, or raising the deployment target.
- Changing the frontmatter schema (bump `schema` and plan a migration first).
- Changing `APP_BUNDLE_ID` or the default data folder location (both must stay stable across renames).
- Disabling, skipping, or weakening a test.

## What you can't verify

You can't click permission dialogs, press global hotkeys, judge focus or animation, or see the UI. For **Manual** acceptance criteria, don't claim success: list them under "Manual checks remaining" in your summary.

## Code style

- Swift 6 language mode, strict concurrency. Prefer value types and actors; inject dependencies through initializers.
- Swift Testing for tests (`import Testing`, `@Test`, `#expect`); fakes for every system client.
- No force unwraps or `try!` outside tests. Typed errors for codec and store failures.
- `os.Logger`, subsystem = the bundle identifier (`Bundle.main.bundleIdentifier`), one category per area (`capture`, `store`, `index`, `provider.safari`, ...).
- Signposts around capture-to-card (NFR-5).
- Formatting by `swift-format` (`.swift-format`); run `make format`.
