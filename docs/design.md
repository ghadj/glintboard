# Glintboard — design doc (MVP)

Sep 29, 2026 · @Georgios Hadjiantonis

**Origin**: inspired by Scott Jenson's talk [Are we really going to use the same Desktop UX forever?](https://www.youtube.com/watch?v=V7AfAcQwLW0) (KDE, 2026), which argues that the deepest desktop innovations come from mundane areas like richer input and better data flows.

## Overview

Glintboard is a lightweight, open source macOS shelf and mood board for things you collect: a clipboard that remembers where everything came from. Every scrap keeps a live reference to its source, so you can jump back, paste with attribution, and trust what you saved. The idea builds on a concept Scott Jenson presented for rethinking the desktop clipboard.

**Goals**

- Capture text, links, files, and images in one keystroke or drag, with their source recorded automatically.
- Make every reference actionable: open the source at the exact spot, or paste with a link.
- Organize with little effort: automatic grouping by source, plus a few deliberate collections.
- Stay invisible on resources: near-zero CPU at idle, small memory footprint, no background network by default.
- Arrange any collection visually as a mood board, with every image and snippet still linked to its source.
- Let you annotate any scrap with your own note, kept beside the captured content and its source.

**Non-goals for the MVP**

- Full clipboard history of everything ever copied. Passive capture is opt-in; deliberate capture is the default.
- Browsers other than Safari, and apps beyond the MVP providers.
- Sync across devices, collaboration, or a cloud service.
- AI features. They come after 0.1, and the 0.1 file format already reserves what they need.

**Principles**

1. Reference first. A scrap without provenance is a bug to fix, not a normal state; the universal fallback guarantees at least app and window.
2. Lightweight and native. Swift with Apple's frameworks only (AppKit, SwiftUI, SQLite3, ScreenCaptureKit, QuickLook): no third-party packages, no Electron, no always-on indexing or models.
3. Local first, open format. Data lives in plain files the user owns and can read without the app.
4. Extensible. Each source is a provider behind one small interface, so contributors can add apps.

## Data model

A scrap is content plus exactly one reference; the reference is where the value lives. Content is always snapshotted, so a scrap stays useful even when its source disappears. Captured text is immutable: the app never edits a scrap's body after capture, and corrections go in the note.

**Scrap**

| Field | Type | Notes |
| --- | --- | --- |
| id | UUID | Stable and authoritative; file names are for humans and never parsed |
| kind | text, link, file, image | Drives rendering and paste behavior |
| content | Markdown body or asset path | Text and links are the file body; images live in assets/ (up to 20 MB); files are referenced, never copied, with a text snapshot of up to 1 MB kept in assets/ |
| title | string | Auto-derived (first line, page title, subject), editable |
| collection | folder | Implied by the containing folder, never stored in the file; defaults to Inbox |
| pinned | bool | Pinned scraps sort first and are never auto-pruned |
| created | timestamp | Capture time |
| reference | Reference | See below |
| board | string (fractional rank) | Board sort key; moving a card rewrites only that card's file |
| note | string (Markdown) | Your own annotation; optional, stored apart from content |
| noteUpdated | timestamp | When the note last changed |
| schema | integer | Frontmatter schema version, starting at 1; lets future versions migrate files safely |
| updated | timestamp | Last capture or edit; a duplicate capture bumps it; drives time sorting |
| derivedFrom | list of ids | Scraps this one was built from (AI summaries, merges); empty for captures. Reserved in schema 1 |
| aiExcluded | bool | Keeps the scrap out of every AI feature; also settable per collection. Reserved in schema 1 |

**Reference**

| Field | Type | Notes |
| --- | --- | --- |
| provider | string | safari, mail, files, screenshot, fallback |
| app | bundle id | From the last external frontmost app; left out only when none was known. The name is looked up when shown |
| window | string | Window title at capture time |
| locator | provider-specific | URL, Message-ID, file path (with its base64 bookmark in a `bookmark` key beside it), or capture rect |
| deepLink | URL | What "Open source" launches, e.g. text-fragment URL or message:// |
| label | string | Short line shown on the card, e.g. "zillow.com" or "Mail · landlord" |
| fingerprint | hash | SHA-256 of the captured text after NFC and whitespace normalization (image bytes for images); used for change detection and duplicates |
| status | ok, changed, trashed, missing, unknown | Kept in the index only, so health checks never rewrite user files |
| lastChecked | timestamp | Index only, like status |

**Collection**: a folder. Its name is the folder name; display order and creation date live in a small .collection.json inside it. Grouping by source or time is computed at display time and never stored.

## Capture pipeline

Capture runs in two stages so the shelf always responds instantly: the snapshot and fallback reference are saved first, and providers enrich the reference afterwards.

&#91;embedded content: capture pipeline · 3 triggers, 1 filter, 2 stages\]

**Triggers**

- Hotkey (⌃⌥C): reads the selection through the Accessibility API (`kAXSelectedTextAttribute`). If the app doesn't expose it, Glintboard sends ⌘C, reads the pasteboard, then restores the previous pasteboard contents.
- Drag onto the shelf: reads all dragged pasteboard types, including file promises such as `.eml` from Mail.
- Passive copy (opt-in): polls `changeCount` and captures every copy; off by default so idle cost stays at zero.
- Screenshot hotkey (⌃⌥S): region capture via ScreenCaptureKit, recording app, window, and Safari URL at that moment, then entering the same pipeline.

## Provenance providers

The MVP ships five providers behind one protocol; the first provider that claims a capture wins, and the fallback always runs last.

| Provider | Claims when | Locator | Deep link | Change check |
| --- | --- | --- | --- | --- |
| Safari | Frontmost app is Safari | Tab URL + title via AppleScript | URL with `#:~:text=` fragment built from the copied text | Refetch page, search for fingerprint text |
| Mail | Frontmost app is Mail | Message-ID of selected message | `message://%3C<id>%3E` | Resolve ID via AppleScript; missing if not found |
| Files | Pasteboard holds file URLs, or window exposes `AXDocument` | Path plus bookmark (not security-scoped; the app isn't sandboxed) | `file://` path, revealed in Finder | Resolve bookmark; changed if modification date moved |
| Screenshot | Own capture hotkey | Capture rect + app, window, and URL if Safari | Delegates to Safari or Files when possible | None (snapshot only) |
| Fallback | Always | App bundle id + window title | Activate the app | None |

**Provider protocol (Swift)**

```swift
/// Runs off the main actor. Every system call inside has an explicit short timeout.
protocol ProvenanceProvider: Sendable {
    var id: ProviderID { get }

    /// Cheap and synchronous: decides from the context alone, no I/O.
    func claims(_ context: CaptureContext) -> Bool

    /// Builds the reference. The registry waits up to 300 ms, then stores the
    /// fallback and applies this result when it arrives.
    func makeReference(for context: CaptureContext) async throws -> Reference

    /// Opens the source in its app.
    func open(_ reference: Reference) async throws

    /// Health check for the index; never writes the scrap file.
    func checkHealth(of reference: Reference, fingerprint: Fingerprint) async -> ReferenceStatus
}

/// Immutable snapshot taken at trigger time, before any Glintboard UI appears.
struct CaptureContext: Sendable {
    let trigger: CaptureTrigger            // hotkey, drop, screenshot, passive
    let items: [PasteboardItemSnapshot]    // types and data copied out of NSPasteboard
    let sourceApp: AppIdentity?            // last external frontmost app
    let windowTitle: String?
    let capturedAt: Date
}
```

`CaptureContext` is captured the moment a capture is triggered, using the last external frontmost app (tracked through NSWorkspace activation notifications), so later focus changes can't corrupt it. Apple Events and Accessibility calls carry explicit timeouts of about 250 ms, because their defaults can block for seconds or, for Apple Events, around two minutes when the target app is busy.

**Known edge cases**

- Safari tab switch between copy and query: prefer a page URL embedded in Safari's rich pasteboard data if present; otherwise query at once and mark the reference unverified if the frontmost tab changed within the capture window.
- Safari private windows: spike S2-1 determines whether private windows can be detected. If they can, their URLs are never stored; if not, the policy and a matching setting are decided before release.
- Mail selection versus open message window: prefer the front message window's message over the list selection.

## Shelf UI

The shelf is the whole MVP interface: a 300 pt wide floating panel that shows one collection at a time, groups its scraps, and expands any scrap into a reference card. There is no separate workspace window in the MVP.

The one other surface is the **board view**, a mood board for a single collection, described in the next section.

**Layout, top to bottom**

1. Header: collection switcher (name + chevron menu), search, and the open-board button; keeping the shelf pinned open is an option in the switcher menu.
2. Grouping chips: By source (default), By time, Pinned, plus an Unavailable filter that appears only when some sources are in the Trash or missing.
3. Group headers: source icon, label, and count, e.g. "zillow.com · 3" or "Mail · landlord · 1".
4. Scrap cards: two lines of content, plus a status icon on the right when the reference is changed or missing.
5. Drop zone at the bottom: "Drop here or press ⌃⌥C".

**Reference card (selected scrap)**

Selecting a scrap expands it in place to show the locator line, capture time and app, reference status, and two actions: Open source and Copy with link. Only one card is expanded at a time.

**Window behavior**

- Built as an `NSPanel` (non-activating, floating), so opening it never steals focus from the app you are copying from.
- Summoned by hotkey (⌃⌥V) or by dragging a file to a screen edge; dismissed by Esc or clicking elsewhere unless pinned.
- Remembers size and position per display.

**Interactions**

| Action | Mouse | Keyboard |
| --- | --- | --- |
| Capture current selection | Drag onto shelf | ⌃⌥C (global) |
| Open shelf | Drag to screen edge | ⌃⌥V (global) |
| Navigate scraps | Click | ↑ ↓ |
| Paste scrap into previous app | Double-click | Return |
| Paste with link | Shift-drag out | ⇧Return |
| Open source | Click Open source | ⌘O |
| Move to collection | Drag onto switcher | ⌘1 to ⌘9 |
| Pin / delete | Context menu | ⌘P / ⌫ |
| Search | Click search | Type to filter |
| Clear unavailable scraps | Collection switcher menu | None |

**Drag out** writes several pasteboard types at once (plain text, RTF with source link, file URL or image), so each target app takes the richest one it supports.

## Notes on scraps

Every scrap can carry one note: your own words about why you saved it. The note is stored apart from the captured content, so the snapshot and its fingerprint stay exactly as captured, and reference checks never mistake your note for a change at the source.

&#91;embedded content: notes on scraps · shelf and board\]

**Adding a note**

- On the shelf: click "Add a note…" in the expanded card, or press ⌘N with a scrap selected. The panel takes keyboard focus only while you type, then hands focus back to the app you came from.
- Right after capture: a small "Captured · Add note" toast shows for 4 seconds; clicking it opens the note field on the new scrap.
- On the board: double-click a card's note area, or press ⌘N on the selected card.

**Display**: collapsed shelf cards show the note's first line under the content in secondary text, and board cards show up to two lines. Scraps with a note get a small `note.text` icon beside their source label.

**Format**: plain text with basic Markdown (links, bold, lists). Notes are searchable and saved automatically as you type, debounced by 500 ms.

**Paste and export**: Copy with link pastes the captured content and its source; holding ⌥ adds the note too. Every export includes each scrap's note under its content.

## Board view (mood board)

The board view is a resizable window that shows one collection as an auto-arranged grid, like a mood board. It uses the same scraps and files as the shelf; the only extra data is each card's order in the grid.

&#91;embedded content: board view mockup · callouts 1–4 explained below\]

1. **Toolbar**: zoom from 25% to 200%, and Export. Cards are always laid out automatically in a masonry grid, so there is no manual arranging step.
2. **Reference strip**: selecting a card shows capture details plus Open source and Copy with link, exactly as on the shelf.
3. **Source badge**: every card shows its site, app, or file type, so attribution is visible without clicking.
4. **Status on the card**: a changed, trashed, or missing source shows its icon on the card itself, and the card stays on the board with its snapshot until you clear it.

**Interactions**

| Action | How |
| --- | --- |
| Open board | Board button in the shelf header, or ⌘B with the shelf focused |
| Reorder | Drag a card to a new spot; the grid reflows around it |
| Zoom | Pinch, or ⌘+ / ⌘−; ⌘0 resets to 100% |
| Add from outside | Drop from Finder or Safari onto the canvas; it goes through the normal capture pipeline and is inserted where it was dropped |
| Delete | ⌫ moves the scrap to Trash |
| Clear unavailable | Toolbar button, shown when any card's source is in the Trash or missing |

**Export**: PNG or PDF of the board, with an optional credits page listing every card's source. That's handy when sharing inspiration with a client or team.

**Performance**: the board is a virtualized NSCollectionView with a custom masonry layout (a SwiftUI Layout would create every card up front), so only cards in or near the visible area exist and load thumbnails, rendered at display size. Closing the window releases everything.

## Visual specification

Glintboard uses only system fonts, semantic colors, and SF Symbols, so it matches macOS in light and dark mode and respects accessibility settings without custom theming.

&#91;embedded content: shelf mockup · 1:1 with measurements\]

**Sizes and spacing**

| Element | Value |
| --- | --- |
| Shelf width | 300 pt default, resizable 260–420 |
| Shelf height | 520 pt default, min 320 |
| Panel corner radius / padding | 12 pt / 12 pt |
| Header / chips row / drop zone | 40 pt / 28 pt / 52 pt |
| Card radius / padding / gap | 8 pt / 10 pt / 8 pt |
| Image thumbnail on shelf | 32 pt square, 4 pt radius |
| Board column width | 240 pt; column count follows the window width |
| Board grid gap | 12 pt |

**Type** (SF Pro, system font)

| Use | Style |
| --- | --- |
| Collection name, card titles | 13 pt semibold |
| Card content | 13 pt regular, clamped to 2 lines on the shelf |
| Group headers, metadata, badges | 11 pt regular, secondary label color |

**Color**

- Panel: `NSVisualEffectView` with the popover material, so it blends with the desktop.
- Text: `labelColor` and `secondaryLabelColor`; separators: `separatorColor`.
- Selection and primary actions: the user's accent color (`controlAccentColor`).
- Status: `systemOrange` for changed and in Trash (different symbols), `systemRed` for missing; ok is shown only inside the expanded card, never as a badge.

**SF Symbols**: `magnifyingglass`, `rectangle.on.rectangle` (open board), `pin`, `link`, `clock`, `exclamationmark.triangle` (changed), `trash` (in Trash), `xmark.circle` (missing). Source icons: `safari`, `envelope`, `folder`, `camera.viewfinder`, `app.dashed` (fallback).

**States**

- Hover: card gets a quaternary fill.
- Selected: 1.5 pt accent border; on the shelf the card expands in place.
- Dragging: the source card dims to 60% while a lifted copy follows the pointer.
- Drop target: the drop zone border turns accent and the panel gets a faint accent tint.
- Empty collection: "Nothing here yet. Press ⌃⌥C or drop something."
- Missing permission: a one-line banner at the top of the shelf with a Fix button that opens the right System Settings pane.

**Motion**: new cards slide in over 0.2 s, expand and collapse take 0.18 s, and all motion is replaced by fades when Reduce Motion is on.

**Accessibility**: every card has a VoiceOver label like "Text scrap from zillow.com, source OK", and everything on the shelf and board is reachable by keyboard.

## Reference health and management

References are checked lazily and cheaply, so the shelf can show which sources still match without any constant background work.

**Status checks**

- Local file references are checked every time their card becomes visible (at most once a minute per scrap) and immediately when Open source fails, since resolving a bookmark is a fast local call. Results go to the index only; checks never modify scrap files.
- Web checks are opt-in (off by default), limited to 2 concurrent requests, and never run on battery below 20% or on Low Power Mode.
- Mail references are checked when displayed, at most every 24 hours, and only while Mail is already running, because an Apple Event would otherwise launch Mail. Any reference can also be rechecked from the context menu.

| Status | Meaning | Icon |
| --- | --- | --- |
| ok | Source resolves and fingerprint text is still present | none (quiet by default) |
| changed | Source resolves but the captured text is gone or the file was modified | warning triangle |
| trashed | The file is in the Trash (bookmarks follow files there), or the Mail message is in a Trash mailbox | trash can |
| missing | URL fails, message not found, or file bookmark cannot resolve | broken link |
| unknown | Never checked, or provider has no check | none |

**Unavailable sources**

A scrap whose source is trashed or missing is never removed automatically; it stays on the shelf and the board with its snapshot intact until you clear it.

- The card shows the status icon and a short line, "Source in Trash" or "Source missing".
- Open source on a trashed file reveals it in the Trash so you can put it back. When the file returns, the next check sets the status back to ok.
- **Clear Unavailable…** (collection switcher menu and board toolbar) moves every scrap in the collection whose source is trashed or missing to Glintboard's Trash, after a confirmation showing the count. Pinned scraps are skipped unless you tick "Include pinned". Cleared scraps can be recovered from Glintboard's Trash.
- An **Unavailable** filter chip appears on the shelf whenever the collection has such scraps, so you can review them before clearing.

**Collections**

- Every new scrap lands in the active collection; Inbox is the default and cannot be deleted.
- Collections are flat (no nesting) in the MVP.

**Duplicates**

A capture whose fingerprint and locator match an existing scrap in the same collection updates that scrap's updated timestamp, moving it to the top, instead of creating a new one.

**Retention**

Retention is opt-in and off by default, since Glintboard's promise is persistence. When enabled, unpinned scraps in Inbox older than a configurable age (default 30 days) are moved to Trash, which empties after another 30 days. Scraps in named collections are never pruned.

## Storage and export

Plain Markdown files are the source of truth, and a small SQLite index is a disposable cache for fast search. Delete the index and the app rebuilds it; delete the app and your scraps are still readable.

**Layout on disk** (default `~/Library/Application Support/<bundle id>/Library`, relocatable to any folder)

```
Library/
  Inbox/
    .collection.json
    2026-09-30-0915-b204.md
  Apartment hunt/
    .collection.json
    2026-09-29-1402-8f3a.md
    2026-09-29-1410-c71e.md
    assets/c71e-floorplan.png
  .index.sqlite        (search cache and reference health, rebuildable)
  .trash/
```

**Scrap file**

```markdown
---
schema: 1
id: "8f3a0c2d-5d0f-4c8e-9a51-3c1e7a2b71e4"
kind: "text"
title: "2BR on Elm St"
pinned: false
board: "a3"
created: 2026-09-29T14:02:11Z
updated: 2026-09-29T14:02:11Z
reference:
  provider: "safari"
  app: "com.apple.Safari"
  window: "2BR Apartment - Zillow"
  locator: "https://www.zillow.com/homedetails/4471"
  deepLink: "https://www.zillow.com/homedetails/4471#:~:text=2BR,laundry"
  label: "zillow.com"
  fingerprint: "sha256:9b2f..."
note: |
  Close to work, but ask about parking.
noteUpdated: 2026-09-29T14:05:40Z
---
2BR, 850 sq ft, $2,400/mo, in-unit laundry
```

Keys with no value are left out, and `derivedFrom` and `aiExcluded` appear only when set. Image and file scraps add a top-level `asset` (the stored image or the file's thumbnail), and file scraps (and images whose original file is referenced) a `bookmark` in `reference`. Decision 0017 lists every key, the writing rules, and the YAML subset the app reads.

Frontmatter keeps the files compatible with Obsidian and static-site tools. The app watches the folder with FSEvents, so edits made outside the app show up on the shelf.

**Native implementation**: the index uses the SQLite library built into macOS through its C API, with FTS5 for search (falling back to FTS4 if FTS5 isn't compiled in). Foundation has no YAML parser, so frontmatter is read and written by a small, strict YAML-subset codec in ScrapKit that covers exactly this schema. Note Markdown renders with `AttributedString(markdown:)`.

**Export**

- Collection to a single Markdown file, one section per scrap with its note and source link.
- Collection to JSON with full metadata, for scripts.
- Copy collection as one formatted block (Markdown or rich text with links).
- Because the storage is already files, "export" to Obsidian is pointing the storage folder at a vault subfolder.

## Architecture

ScrapKit is one Swift package split into three targets, named for the domain rather than the product, so the layering is enforced by the build (target dependencies, caught by the compiler on clean builds) and by `scripts/check-layering.sh` in `make check`: lower layers can't import higher ones, and nothing below the app imports AppKit.

| Layer | Contents | Depends on |
| --- | --- | --- |
| ScrapModel | Scrap, Reference, and Collection types; YAML-subset codec; fingerprints; fractional ranks; text-fragment builder | Foundation, CryptoKit |
| ScrapStorage | File store actor (atomic writes, folder watcher, self-echo suppression); index actor (SQLite3, FTS5, reference health); launch reconciliation | Model, SQLite3 |
| ScrapCapture | Capture pipeline, privacy filter, provider protocol and registry, provider logic written against system-client protocols | Model, Store |
| App | AppKit shell (menu bar, NSPanel, windows), SwiftUI views, NSCollectionView board, and the real system clients: pasteboard, Accessibility, Apple Events, ScreenCaptureKit, hotkeys | All of the above |

**Concurrency**: UI runs on the main actor; the file store and the index are separate actors; providers are Sendable and run on the cooperative pool. Anything that can block (Apple Events, Accessibility, large file reads) sits behind an async API with a timeout and never runs on the main actor.

**System access rules**

- Apple Events are always sent with an explicit short timeout (for example through NSAppleEventDescriptor's sendEvent(options:timeout:)), never the default. Automation permission is checked with AEDeterminePermissionToAutomateTarget without prompting, so banners appear only after a real denial.
- Accessibility calls set AXUIElementSetMessagingTimeout to about 250 ms.
- The synthetic ⌘C fallback is skipped while secure event input is on (password fields), and the restored clipboard is marked transient so other clipboard tools ignore it.
- The app tracks the last external frontmost app through NSWorkspace activation notifications; captures, drops onto the board, and paste into previous app all rely on it.

**File watching**: the store remembers its own recent writes (path and content hash) and ignores the matching FSEvents echoes. At launch, a background reconciliation compares file modification dates with the index and repairs any differences.

**Logging and localization**: os.Logger with captured content always logged as private, and every user-facing string in a String Catalog from the first commit.

**Naming**: the product name appears only in one branding file, the app icon, and user-facing docs. Code and modules use neutral names, and the bundle identifier (io.github.ghadj.glintboard), which also names the data folder and log subsystem, never changes, so renaming the app later changes only its display name, without touching code, data, or the permissions users already granted. The architecture plan lists the details.

## Resource budget

In the default mode Glintboard does no periodic work at all: capture is triggered by the hotkey or a drag, so the app sleeps until you use it. These targets are release blockers, measured on an M1 MacBook Air as physical footprint (the footprint tool). M0 records the baseline of an empty menu bar app, so the memory targets can be confirmed or adjusted early.

| Metric | Target | How |
| --- | --- | --- |
| Idle CPU, default mode | 0% (no timers) | Event-driven capture only |
| Idle CPU, passive capture on | < 0.1% average | Poll `changeCount` every 0.5 s with timer tolerance; pause on sleep, screen lock, and Low Power Mode |
| Memory, shelf closed | < 40 MB resident | Release views and thumbnails when the panel closes |
| Memory, shelf open | < 80 MB with 500 scraps | Lazy list, thumbnails via `QLThumbnailGenerator`, no full images in memory |
| Launch to menu bar | < 0.5 s | Index opened lazily on first shelf open |
| Capture to card visible | < 150 ms | Snapshot and fallback reference first, provider enrichment async |
| Energy Impact | "Low" in Activity Monitor | No background network by default |
| App size | < 15 MB | Native Swift, no third-party dependencies |

**Rules for contributors**

- No always-on timers; every timer must have tolerance and a reason in code review.
- No work on the main thread beyond UI; providers run on a background actor.
- No bundled ML models or runtimes in the core app.
- No third-party packages or runtimes; if Apple's frameworks don't cover something, write a small, tested implementation in ScrapKit.

## Privacy, permissions, and distribution

Glintboard asks for each permission only when the feature that needs it is first used, and works in a reduced mode if the user declines.

| Permission | Needed for | If declined |
| --- | --- | --- |
| Accessibility | Reading selected text and window titles; pasting into the previous app | Drag-in only; references fall back to app name |
| Automation: Safari | Tab URL and title | Safari scraps get the fallback reference |
| Automation: Mail | Message-ID of the selected message | Mail scraps get the fallback reference |
| Screen Recording | Screenshot capture via ScreenCaptureKit | Screenshot provider disabled |

Recent macOS versions may periodically ask users to re-confirm Screen Recording access for apps that use it, so onboarding should mention that the screenshot feature can prompt again over time.

**Privacy rules**

- Never store pasteboard items marked `org.nspasteboard.ConcealedType` or `TransientType` (password managers use these).
- User-editable app exclusion list, prefilled with password managers.
- No telemetry and no network requests except opt-in web reference checks and an opt-in cloud AI backend.
- Safari private windows: URLs from windows detected as private are never stored; spike S2-1 settles how detection works.

**Distribution**

- MIT license (decision 0015), source on GitHub.
- Signed and notarized builds via GitHub Releases and a Homebrew cask; not the Mac App Store, whose sandbox makes Automation and Accessibility access much harder.
- Hardened runtime with the Apple Events entitlement and `NSAppleEventsUsageDescription`.
- Minimum macOS 15 (Sequoia), which covers the current SwiftUI and ScreenCaptureKit APIs the app uses (decision 0013).

## AI assist (after 0.1)

AI turns each board into something you can search, ask, and cite: answers point to the exact scraps they used, and from there to the original page, message, or file. It is off until the user turns it on, prefers on-device models, and only proposes changes for the user to confirm.

- **Suggested collection** for a new scrap, shown as a one-tap chip on the card.
- **Auto titles** for scraps whose first line is a poor title.
- **Duplicate spotting** across sources (same listing on two sites).
- **Summarize with citations** for a collection, saved as a new scrap whose references point to the source scraps.
- **Ask a board**: questions answered from one board or all of them, with citation chips that open the cited scraps.
- **Semantic search**: find scraps by meaning, including text inside images and captured files.
- **Agents and system search**: a read-only MCP server lets tools such as Claude Desktop or Claude Code search and cite your boards, and App Intents expose scraps to Shortcuts and Spotlight.

Backends are pluggable behind one protocol: Apple's on-device Foundation Models framework first (no download, no network), then Ollama or a cloud API key for heavier tasks. Nothing is bundled in the core app, which keeps the resource budget intact.

Excluded scraps and collections never reach any AI feature, and captured web text is always treated as data, never as instructions. The architecture plan's "AI extension" section covers retrieval, citations, backends, and safeguards in detail.

## MVP scope and milestones

The MVP is done when a user can capture from Safari, Mail, Finder, and screenshots with the hotkey, see scraps grouped by source on the shelf, open any source, and paste with a link, all within the resource budget.

1. **Skeleton**: menu bar app, `NSPanel` shelf, Markdown storage, SQLite index, drag in and out, fallback provider.
2. **References**: Safari, Mail, and Files providers; reference card with Open source and Copy with link.
3. **Capture**: global hotkey, Accessibility-based selection read, screenshot provider, concealed-type filtering.
4. **Management**: collections, notes, grouping chips, search, duplicates, retention, local reference checks.
5. **Board view**: mood board window per collection, auto-arranged grid with drag-to-reorder, image-first cards, source badges.
6. **Release**: resource budget verification, onboarding for permissions, notarized build, Homebrew cask, contributor guide for writing providers.

**Out of MVP**: passive capture, web reference checks, AI assist, other browsers.

## Open questions

- Default hotkeys: ⌥⌘C and ⌥⌘V clash with Finder's Copy as Pathname and Move Item Here. This doc uses ⌃⌥C and ⌃⌥V instead; confirm they don't collide with common apps, and make both configurable.
- Project name: "Glintboard" is the working name; confirm GitHub, Homebrew, domain, and trademark availability before the first public release.
- AI assist via Foundation Models needs macOS 26 and an Apple Intelligence Mac, while the app targets macOS 15; the feature should simply hide where unavailable.
- Paste into previous app writes the scrap to the clipboard before sending ⌘V. Proposed default: restore the previous clipboard right after pasting, with a setting to keep the pasted scrap instead.
