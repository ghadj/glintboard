# Glintboard — Architecture plan

Oct 1, 2026 · @Georgios Hadjiantonis

## Purpose and drivers

Glintboard is a native macOS menu bar app built as a thin AppKit shell over a three-layer Swift package, with plain Markdown files as the source of truth and every system call isolated behind a timeout. This plan is the "how" behind the [design doc](https://claude.ai/code/artifact/b3765123-d32d-46cd-bf87-3bbb79893739) (the "what") and `docs/milestones.md` (the "when"). Where they disagree, the design doc wins for behavior and this plan wins for structure.

When two goals conflict, the higher one wins:

| Rank | Driver | What it means for the architecture |
| --- | --- | --- |
| 1 | Data safety | Atomic writes, files as source of truth, no rewrites of user files by background work, a schema version on every file |
| 2 | Privacy | Filtering at the capture boundary, private logging, no network by default |
| 3 | Responsiveness | Nothing blocks the main actor; every system call has a timeout; capture shows a card in under 150 ms |
| 4 | Resource budget | Event-driven only, lazy loading, virtualized views, zero idle CPU |
| 5 | Native only | Apple frameworks only; small in-house implementations where Foundation stops |
| 6 | Testability | All system access behind protocols with fakes; logic lives below the app layer |
| 7 | Extensibility | New sources are new providers, never pipeline changes |

Out of scope for this plan: multiple Macs writing one library, sync, and the post-MVP AI assist, beyond the extension points named in "Extensibility".

## System context

Glintboard talks to macOS through system APIs, to Safari and Mail through Apple Events, and to the outside world only through a folder of plain files that other editors can open too.

&#91;embedded content: system context · Glintboard, macOS services, captured apps, library folder\]

The library folder is the only shared state: Glintboard writes it atomically and listens for changes, so edits made in Obsidian or a text editor show up on the shelf. Nothing in the MVP touches the network.

## Module structure

The app is four layers with one-way dependencies: three targets in the `ScrapKit` package, plus the app target on top. The package makes the rules enforced rather than conventions: target dependencies make a clean build fail on a forbidden import, and because incremental builds can miss one (spike S0-1), `scripts/check-layering.sh` checks every library target's imports (not the test targets) in `make check`.

&#91;embedded content: module structure · 4 layers, the Apple frameworks each uses\]

**Dependency rules**

- A layer imports only the layers below it. `ScrapModel` imports nothing but Foundation and CryptoKit.
- Nothing below App imports AppKit, SwiftUI, or ApplicationServices. Core reaches the system only through protocols that App implements.
- A fourth target, `ScrapTestSupport`, holds fakes and fixture loaders and is linked only by test targets.
- Public API is deliberate: types are `internal` unless another layer needs them, and every public type is `Sendable`.

## Key types and protocols

Each layer exposes a small public surface; everything else is `internal`. These signatures are the starting contract, refined in each milestone's plan.

**ScrapModel**: pure values, no I/O.

```swift
public struct ScrapID: Hashable, Sendable, Codable { public let raw: UUID }

public struct Scrap: Sendable, Equatable {
    public var id: ScrapID
    public var schema: Int                 // starts at 1
    public var kind: ScrapKind             // .text, .link, .image, .file
    public var title: String
    public var body: String                // text and links; empty for images and files
    public var asset: AssetRef?            // images, file thumbnails
    public var pinned: Bool
    public var board: Rank
    public var created: Date
    public var updated: Date
    public var reference: Reference
    public var note: Note?
    public var extraFrontmatter: [String: FrontmatterValue]  // unknown keys, preserved
}

public struct Reference: Sendable, Equatable {
    public var provider: ProviderID
    public var app: AppIdentity?
    public var window: String?
    public var locator: Locator            // .url, .messageID, .file(path:bookmark:), .screenRect
    public var deepLink: URL?
    public var label: String
    public var fingerprint: Fingerprint
}

public enum FrontmatterCodec {
    public static func decode(_ text: String) throws(CodecError) -> Scrap
    public static func encode(_ scrap: Scrap) -> String
}

public struct Rank: Comparable, Sendable, Codable {
    public static func between(_ a: Rank?, _ b: Rank?) -> Rank
}
```

**ScrapStorage**: the only layer that touches the library folder.

```swift
public actor ScrapStore {
    public init(root: URL, fileSystem: FileSystem, clock: WallClock)
    public func load() async throws -> LibrarySnapshot
    public func save(_ scrap: Scrap, in collection: CollectionName) async throws
    public func move(_ id: ScrapID, to collection: CollectionName) async throws
    public func trash(_ id: ScrapID) async throws
    public var changes: AsyncStream<LibraryChange> { get }   // external and internal, deduplicated
}

public actor ScrapIndex {
    public init(databaseURL: URL)
    public func apply(_ change: LibraryChange) async throws
    public func search(_ query: SearchQuery) async throws -> [ScrapID]
    public func health(of id: ScrapID) async -> ReferenceHealth?
    public func setHealth(_ health: ReferenceHealth, for id: ScrapID) async throws
}
```

**ScrapCapture**: the pipeline and providers, written against system-client protocols.

```swift
public protocol AppleEventClient: Sendable {
    func send(_ event: AppleEventRequest, to app: AppIdentity, timeout: Duration) async throws -> AppleEventReply
    func permission(for app: AppIdentity) async -> AutomationPermission   // never prompts
}

public protocol AccessibilityClient: Sendable {
    func focusedWindowTitle(of app: AppIdentity, timeout: Duration) async -> String?
    func selectedText(in app: AppIdentity, timeout: Duration) async -> String?
    func documentURL(of app: AppIdentity, timeout: Duration) async -> URL?
}

public actor CaptureCoordinator {
    public init(store: ScrapStore, registry: ProviderRegistry, filter: PrivacyFilter, clock: WallClock)
    public func capture(_ context: CaptureContext) async -> CaptureOutcome   // .saved(ScrapID), .filtered, .failed
}
```

`ProvenanceProvider` and `CaptureContext` are as defined in the design doc. `PasteboardClient`, `WorkspaceClient`, `ThumbnailClient`, `FileSystem`, and `WallClock` follow the same pattern: a protocol in Core, a real implementation in the app, a fake in tests. The clock is named `WallClock` to avoid clashing with Swift's own `Clock` protocol, which is still used (as `any Clock<Duration>`) for sleeps and timeouts.

## Runtime flows

Every flow starts from an event and ends in a file write or a UI update; the capture flow splits into a fast path that always succeeds and an enrichment step that may time out without consequence.

**Capture**

&#91;embedded content: capture sequence · fast path, then enrichment\]

The trigger snapshots the context (pasteboard items, last external app, window title, time) before any Glintboard UI appears. The coordinator filters it, saves the scrap with the fallback reference, and the card appears. Only then does the claiming provider run; its reference replaces the fallback in a second save, or the fallback stays if the provider times out.

**External edit**

1. FSEvents reports a change to a scrap file.
2. The store hashes it; a ledger match is its own echo and is dropped.
3. Otherwise it parses the file and emits `LibraryChange.updated`, or `.problem` if parsing fails.
4. The index upserts the row, and `LibraryModel` updates the card.

**Health check**

1. A card becomes visible. Local file references are checked if their last check is over a minute old; Mail references if it's over 24 hours old and Mail is already running. A failed Open source or the context menu triggers a check immediately.
2. The provider's `checkHealth` runs with a timeout. For files: a bookmark that resolves inside the Trash means trashed, a failed resolution means missing, and a resolution to a new path refreshes the stored path and stays ok.
3. The result is written to the index's `health` table only, and the card's icon updates. The scrap file is never touched, and trashed or missing scraps stay where they are until the user runs Clear Unavailable.

**Board reorder**

1. The user drops a card between two others.
2. `Rank.between(left, right)` produces the new key.
3. The store saves that one scrap; the layout re-flows from the in-memory order.

**Paste back**

1. Return on a selected scrap: if secure input is on, show a notice and stop.
2. Save the current clipboard, write the scrap's representations, and close the shelf.
3. Post ⌘V to the last external app.
4. After a short delay, restore the saved clipboard marked transient (unless the user disabled restoring).

## Concurrency model

Five isolation domains, each owning its state; they communicate only through async calls and one change stream, so no locks are shared and the Swift 6 compiler can prove data-race safety.

| Domain | Owns | Runs | Talks to |
| --- | --- | --- | --- |
| Main actor | Windows, views, `@Observable` UI models, NSPasteboard writes, hotkey callbacks | Main thread | Everything, via `await` |
| `ScrapStore` actor | Library folder, file writes, recent-write ledger, FSEvents stream | Cooperative pool | Emits `LibraryChange` |
| `ScrapIndex` actor | The single SQLite connection | Cooperative pool | Called by the library model and health checker |
| `CaptureCoordinator` actor | In-flight captures, late provider results | Cooperative pool | Store, registry, providers |
| System clients | Nothing shared; each call is self-contained | A dedicated actor on its own serial queue for Apple Events and Accessibility | Called by providers with timeouts |

**Rules**

1. Value types cross domains; nothing crossing a boundary is a class unless it is an actor or immutable and `Sendable`.
2. Apple Events and Accessibility calls are synchronous IPC. They run on one dedicated actor whose executor is its own `DispatchSerialQueue` (supported as an actor executor from macOS 14), never the cooperative pool, so a hung target app can't starve Swift's thread pool.
3. Every such call has a timeout (250 ms default), enforced by the API's own timeout parameter, and the async wrapper also races a `Task.sleep` so the caller is released even if the system call ignores it.
4. Changes flow one way: store → `AsyncStream<LibraryChange>` → `LibraryModel` (main actor) → views. Views never call the store directly; they call intent methods on the model.
5. Cancellation: closing the shelf cancels thumbnail loads and pending health checks for off-screen cards; captures are never cancelled once the snapshot is taken.
6. FSEvents and NSWorkspace notifications are bridged into `AsyncStream`s at the edge; no `NotificationCenter` observers inside Core.

## UI architecture

AppKit owns windows, focus, and anything performance-sensitive; SwiftUI draws the content inside them. A single composition root builds every dependency at launch and hands them down through initializers.

**Composition root.** `AppEnvironment` (main actor) is created in `applicationDidFinishLaunching` and owns the store, index, coordinator, system clients, settings, and the controllers below. Nothing else creates services, and there are no singletons, so tests and previews build their own environment with fakes.

**Launch sequence**

1. Install the menu bar item and register hotkeys (target: icon visible in under 0.5 s).
2. Start the last-external-app tracker.
3. Open the store and start the FSEvents stream.
4. Open the index lazily on first use, then run launch reconciliation in the background.

**Controllers and models**

| Piece | Kind | Responsibility |
| --- | --- | --- |
| `MenuBarController` | AppKit, main actor | Status item, menu, hotkey actions |
| `ShelfPanelController` | AppKit, main actor | The non-activating `NSPanel`: frame, key-window behavior, show and hide, Esc and click-outside |
| `BoardWindowController` | AppKit, main actor | One window per collection, hosting an `NSCollectionView` with the masonry layout |
| `LibraryModel` | `@Observable`, main actor | Collections, scraps by collection, selection, grouping, search state; consumes the store's change stream |
| `ShelfView`, `ScrapCardView`, `ReferenceCardView`, `NoteEditor` | SwiftUI | Pure rendering of `LibraryModel` state; user actions call model intent methods |
| `SettingsModel` | `@Observable`, main actor | Typed wrapper over `UserDefaults` |

**Why the split.** The shelf list is SwiftUI (`List` is lazy and backed by AppKit on macOS) inside an `NSHostingView` in the panel, which keeps the card UI simple. The board is `NSCollectionView` because a SwiftUI `Layout` creates every card up front, which breaks the memory budget at 500 images. Panel focus behavior is AppKit-only because SwiftUI can't express a non-activating key panel.

**Thumbnails.** One `ThumbnailCache` (an `NSCache` with a cost limit in bytes) serves both surfaces; requests go through `QLThumbnailGenerator` at the requested display size, and the cache empties when both surfaces close.

## Persistence

Files are written atomically and recorded in a short-lived ledger, the index mirrors them and can always be rebuilt, and reconciliation repairs any drift at launch. Only user actions and captures write scrap files.

**Writing a scrap**

1. Encode the scrap with `FrontmatterCodec` (writer output is deterministic: fixed key order, quoted strings).
2. Write to a temporary file in the same folder, then atomically replace the target (same volume, so the rename is atomic).
3. Record `(relative path, SHA-256 of bytes)` in the recent-write ledger for 5 seconds.
4. Upsert the index row and emit `LibraryChange.saved`.

Moves rename the file and its assets within the library root; deletes rename into `.trash/<timestamp>/`.

**Watching.** One FSEvents stream on the library root with file-level events and 300 ms latency. Paths under `.trash/`, `.index.sqlite*`, and temporary files are ignored. For any other event the store hashes the file; a ledger match is the store's own echo and is dropped, anything else becomes an external change.

**Index schema** (SQLite3; `PRAGMA user_version` holds the index schema version, and a mismatch triggers a rebuild):

```sql
PRAGMA journal_mode = WAL;

CREATE TABLE scraps (
  rowid       INTEGER PRIMARY KEY,
  id          TEXT NOT NULL UNIQUE,
  collection  TEXT NOT NULL,
  path        TEXT NOT NULL UNIQUE,   -- relative to the library root
  mtime       REAL NOT NULL,
  size        INTEGER NOT NULL,
  kind        TEXT NOT NULL,
  title       TEXT NOT NULL,
  label       TEXT NOT NULL,
  provider    TEXT NOT NULL,
  pinned      INTEGER NOT NULL,
  board       TEXT NOT NULL,
  created     REAL NOT NULL,
  updated     REAL NOT NULL,
  fingerprint TEXT NOT NULL,
  locator     TEXT
);
CREATE INDEX scraps_recent ON scraps(collection, updated DESC);
CREATE INDEX scraps_board  ON scraps(collection, board);
CREATE INDEX scraps_dupes  ON scraps(collection, fingerprint, locator);

CREATE TABLE health (
  id           TEXT PRIMARY KEY REFERENCES scraps(id) ON DELETE CASCADE,
  status       TEXT NOT NULL,          -- ok, changed, trashed, missing, unknown
  last_checked REAL NOT NULL
);

-- FTS4 fallback uses the same columns with tokenize=unicode61
CREATE VIRTUAL TABLE scraps_fts USING fts5(
  title, body, note, label, window,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3'
);   -- rowid matches scraps.rowid
```

**Reconciliation at launch** (background, after the shelf can open):

1. Enumerate `*.md` files outside dot-folders and compare `(path, mtime, size)` with the index.
2. New or changed files are parsed and upserted; rows whose files are gone are deleted.
3. Two files with the same `id` (usually a copy made in Finder): the older path keeps the id, the newer file gets a fresh id. This is the one case where Glintboard rewrites a file it didn't just save, and it's logged.
4. Files that fail to parse are listed under a "Problems" item in the menu bar menu and never modified.

**Schema evolution.** The reader accepts every frontmatter schema up to the current one; the writer always writes the current one. Files migrate lazily when the user next changes them, never in a bulk rewrite. `.collection.json` follows the same rule.

## Failure modes

Every failure degrades to a still-useful scrap or a clear message; none loses data or freezes the UI.

| Failure | Detection | Behavior |
| --- | --- | --- |
| Safari or Mail hung or slow | Apple Event timeout (250 ms) | Fallback reference saved; card shows it; no retry loop |
| Automation permission denied | `AEDeterminePermissionToAutomateTarget` or error -1743 | Fallback reference; one banner with Fix |
| Accessibility not granted | `AXIsProcessTrusted()` false | Hotkey capture disabled with a banner; drag still works |
| Secure input active | `IsSecureEventInputEnabled()` | Copy and paste-back skipped with a short notice |
| Scrap file unparseable | Codec error | Listed under Problems; file untouched |
| Duplicate ids on disk | Reconciliation | Newer copy gets a fresh id; logged |
| Index missing, corrupt, or old schema | Open fails, integrity check, `user_version` | Delete and rebuild in the background; shelf shows files as they're read |
| FTS5 unavailable | `PRAGMA compile_options` | FTS4 fallback |
| Library folder missing or unmounted | Store open fails or FSEvents root event | Banner with Choose Folder; nothing is created at a guessed path |
| Files evicted by iCloud (if the user put the library there) | Reading returns no data | Treated as unavailable; never rewritten |
| Disk full or write error | Write throws | Capture fails visibly; the temporary file is cleaned up; nothing half-written |
| Captured file deleted or moved | Bookmark resolution | Trashed if the bookmark resolves into the Trash, missing if it can't resolve, refreshed if moved or renamed; the scrap stays until the user clears it |
| Hotkey already taken | `RegisterEventHotKey` error | Shown in Settings and the menu |

## Performance and resources

The app does work only in response to events, keeps nothing heavy in memory while the shelf is closed, and measures its own hot path.

| Budget | Architectural mechanism |
| --- | --- |
| Zero idle CPU | No timers in default mode; FSEvents, NSWorkspace notifications, and hotkeys are the only wake-ups. Retention and health checks run at launch, on wake, or on display, never on a schedule |
| Memory, shelf closed < 40 MB | Closing the shelf releases the hosting view, card models, and the thumbnail cache; `LibraryModel` keeps only ids and sort keys for closed collections |
| Memory, shelf open < 80 MB at 500 scraps | Lazy `List`; cards load title and two lines from the index, not full files; thumbnails at display size with a byte-capped cache |
| Launch < 0.5 s | Status item first; store and index open after the menu is visible; reconciliation in the background |
| Capture to card < 150 ms | Snapshot and fallback reference are saved before providers run; the card renders from the in-memory scrap, not a re-read |
| Board memory returns after close | `NSCollectionView` reuses item views; the board's cache entries are evicted when the window closes |

**Measurement.** Signposts (`OSSignposter`, subsystem `<bundle id>`) mark capture-to-card, index queries, reconciliation, and thumbnail loads. `docs/perf.md` records each milestone's numbers using the seed libraries (500 and 5,000 scraps, 500 images).

## Testing

Most logic sits below the app layer and runs against fakes, so the automated suite covers nearly everything except focus, permissions, and real system apps, which stay on the manual checklists.

| Level | Lives in | Covers | Speed |
| --- | --- | --- | --- |
| Unit | `ScrapModelTests` | Codec round-trips, fingerprints, ranks, text fragments, masonry math, property-style tests with generated inputs | Milliseconds; run on every edit |
| Integration | `ScrapStorageTests`, `ScrapCaptureTests` | Store with a temporary folder and real FSEvents; index with a real SQLite file; pipeline and providers with fake system clients | Seconds |
| App | `AppTests` (Xcode) | Composition root wiring, `LibraryModel` reacting to change streams, controllers with fake services | Seconds |
| Manual | Milestone checklists | Panel focus, hotkeys, permissions, live Safari and Mail, performance numbers | Per milestone |

**Fakes.** Every system-client protocol has a fake in a `ScrapTestSupport` target: `FakeAppleEventClient` (scripted replies, configurable delay to test timeouts), `FakeAccessibilityClient`, `FakePasteboard`, `FakeWorkspace` (activation events on demand), `FakeWallClock`, and `InMemoryFileSystem` for pure store logic.

**Fixtures.** `Fixtures/Library/` holds hand-written scrap files, including edge cases (unknown keys, every schema version, unsupported YAML, duplicate ids); the seed tool generates the large libraries used for performance.

**Determinism.** No test sleeps on the real clock; timeouts are driven through an injected `any Clock<Duration>` and the fake wall clock.

## Extensibility

New sources are new providers; new capabilities attach at the named seams below, so post-MVP work never reshapes the core.

**Adding a provider** (the contributor path in `CONTRIBUTING.md`):

1. Add a case to `ProviderID` and, if needed, a `Locator` case (bump the frontmatter `schema` only if the file format changes).
2. Write `struct XProvider: ProvenanceProvider` in `ScrapCapture`, using only system-client protocols.
3. Add tests with fakes and at least one fixture file.
4. Register it in `ProviderRegistry`'s ordered list in the composition root.
5. Add its SF Symbol and label format to the UI mapping.

**Seams for later work**

| Future work | Seam | What changes |
| --- | --- | --- |
| Other browsers | New providers; a browser extension would post selection context through an XPC service or local socket into `CaptureContext` | No pipeline changes |
| AI assist | `AssistBackend` protocol in a new `ScrapAssist` target, consuming `LibrarySnapshot` and producing suggestions | New Retrieval and Assist targets, MCP helper, App Intents; see "AI extension" |
| Passive capture | A `PasteboardWatcher` that produces `CaptureContext` values like the hotkey does | One new trigger |
| Sync (iCloud folder) | Store already tolerates external edits; needs file coordination and conflict-copy handling | Store only |
| Document-linked collections | A `linkedDocument` field in `.collection.json` plus a provider-side lookup | Additive schema change |

## Source tree

One Xcode project for the app and one local Swift package for everything testable; folders mirror the layers.

```
<repo>/
  App.xcodeproj                  # synchronized folders; rarely edited
  Config/                        # Branding, Base, Debug, Release, Local.xcconfig.example
  App/
    AppEnvironment.swift         # composition root
    AppInfo.swift                # display name and bundle id, read from Info.plist
    MenuBar/                     # MenuBarController, hotkeys
    Shelf/                       # ShelfPanelController, SwiftUI shelf views
    Board/                       # BoardWindowController, masonry NSCollectionViewLayout
    Settings/  Onboarding/
    SystemClients/               # real AppleEvent, Accessibility, Pasteboard, Workspace,
                                 # ScreenCapture, Thumbnail clients
    Resources/                   # Localizable.xcstrings, Assets.xcassets
  AppTests/
  Packages/ScrapKit/
    Package.swift                # no dependencies
    Sources/
      ScrapModel/
      ScrapStorage/
      ScrapCapture/
        Providers/               # Safari, Mail, Files, Screenshot, Fallback
      ScrapTestSupport/          # fakes, fixtures loader
    Tests/
      ScrapModelTests/  ScrapStorageTests/  ScrapCaptureTests/
      Fixtures/Library/
  scripts/                       # bootstrap.sh, check-native-only.sh, check-branding.sh, seed-library
  docs/                          # design.md, architecture.md, milestones.md, plans/, decisions/, perf.md
  .claude/  .github/             # Claude Code settings; CI, PR and issue templates
  Makefile  .xcode-version       # single entry point; pinned Xcode for contributors and CI
  AGENTS.md  CLAUDE.md           # agent-neutral rules; Claude Code imports AGENTS.md
  CONTRIBUTING.md  SECURITY.md
```

## AI extension

The architecture suits AI search, citation, and board-level use well: every scrap already carries a stable id, its own provenance, and a note, collections are ordered, and the index is a rebuildable cache that can hold embeddings. Seven gaps need closing, and three of them must close before the first release because they affect the file format or what gets captured.

&#91;embedded content: AI layer · three surfaces over one retrieval module\]

**Fit assessment**

| Need | Already in place | Gap |
| --- | --- | --- |
| Search across boards | FTS index, collections as folders | No semantic search or passage chunking |
| Citations to sources | Stable scrap ids; every scrap has a reference with a deep link | No anchors inside a scrap; no rule that captured text is immutable |
| Text for every scrap | Text and link scraps have bodies | Images have no text; a referenced file's text is lost if the file disappears |
| AI-made scraps | Planned "summarize with citations" | A scrap has one reference and no way to record what it was derived from |
| A board as context | Ranks, notes, reference labels | No canonical serialization of a board for a model or tool |
| Privacy | No network by default | No way to exclude scraps or boards from AI; network policy doesn't cover AI backends |
| External agents | None | No read interface outside the app |

**Close before the first release** (these change the file format or what is captured):

1. Reserve two frontmatter keys in schema 1: `derivedFrom` (a list of scrap ids) and `aiExcluded` (a boolean, also settable for a whole collection in `.collection.json`).
2. Captured text is immutable: the app never edits a scrap's body after capture, and corrections go in the note. An external edit changes the content hash, which marks existing citations stale instead of silently wrong.
3. Text snapshots for files: at capture, the Files provider extracts up to 1 MB of text (PDFKit for PDFs, Foundation for plain and rich text) into `assets/<short id>.txt`, so the content survives if the source file is deleted.

**Add with the AI milestones** (no file-format change):

| Module | Depends on | Contents |
| --- | --- | --- |
| `ScrapRetrieval` | Model, Storage | Extraction and OCR jobs (Vision), chunker, on-device embeddings, hybrid search, board serializer, `LibraryQuery` tools |
| `ScrapAssist` | Retrieval | `AssistBackend` protocol and implementations, prompt assembly, citation validation, proposals |
| App Intents (in App) | Retrieval | Intents and Spotlight entities for Shortcuts and system search |
| `scrap-mcp` helper executable | Retrieval | Read-only MCP server over stdio for agents such as Claude Desktop or Claude Code |

**Retrieval**

- Bodies, notes, extracted file text, and OCR text are split into passages of about 200 words, each keeping its character range in the source field.
- Embeddings come from the NaturalLanguage framework on device and are stored as Float16 blobs in the index, tagged with the model identifier; a model change triggers re-embedding. At 512 dimensions that is about 1 KB per passage.
- Search merges FTS5 ranking and cosine similarity (computed with Accelerate) by reciprocal rank fusion, filtered by collection, source, date, status, and pinned. Brute-force similarity is fast enough for tens of thousands of passages; an approximate index is only needed beyond that.

**Citations**

```swift
public struct Citation: Sendable, Codable, Hashable {
    public let scrap: ScrapID
    public let field: CitedField          // .body, .note, .extractedText, .ocrText
    public let range: Range<Int>          // character offsets in that field
    public let contentHash: Fingerprint   // of the field when it was cited
    public let quote: String              // the cited words, shown and validated
}
```

- Every claim in an answer carries a citation key such as `[S3]`; the assist layer checks each quote against its range in the current text and marks it stale (hash changed) or rejects it (quote not found).
- Citation chips open the card; from there Open source reaches the original page, message, or file. That two-step provenance, from answer to scrap to source, is what most AI tools can't offer.

**A board as context**: `BoardSerializer` turns a collection into a deterministic Markdown document (scraps in rank order with citation keys, titles, bodies, notes, and source labels and links), skipping excluded scraps and fitting a token budget by summarizing in stages when a board is large.

**Backends**: `AssistBackend` declares its capabilities (on device, context size, tool calling, structured output) and streams responses. Implementations: Apple's Foundation Models framework on device (macOS 26 with Apple Intelligence; the default where available), the Anthropic API through `URLSession` with a user key in the Keychain, and an OpenAI-compatible local server through `URLSession`. All native APIs, no SDKs.

**Surfaces**: one `LibraryQuery` tool set (`search`, `getScrap`, `getBoard`, `getBoardContext`) serves three surfaces: tool calling inside the Ask panel, the MCP helper, and App Intents. The MCP helper opens the index read-only (SQLite's WAL mode allows concurrent readers) and never writes.

**Safety and privacy**

- AI is off by default; on-device processing is preferred, and a cloud backend needs an explicit setting and key. The first cloud request for a board shows what will be sent.
- Excluded scraps and collections are skipped everywhere: no extraction, embedding, prompts, or MCP results.
- Captured web text can carry prompt injection. Scrap text is always passed as delimited data, and AI output can only propose changes (new scraps, titles, moves) that the user confirms; nothing writes files on a model's say-so.
- The network rule becomes "no network except opt-in web checks and an opt-in cloud AI backend".

**Resources**: with AI off, nothing is built or loaded. With AI on, extraction, OCR, and embedding run right after each capture and in a one-time backfill the user starts, at utility priority, paused on battery below 20% and in Low Power Mode. Models load on first use and unload when the Ask panel closes.

## Naming and branding

The product name lives in one build-settings file; code and modules use neutral names, and everything that data or macOS permissions depend on uses a permanent identifier that never changes, so a rename is a one-line change plus new artwork.

| Thing | Name | Changes on rename? |
| --- | --- | --- |
| Display name, menus, About, onboarding | `APP_DISPLAY_NAME` in `Config/Branding.xcconfig`, read at runtime through `AppInfo.displayName` | Yes, one line |
| `.app` bundle file name | `PRODUCT_NAME = $(APP_DISPLAY_NAME)` | Yes, automatically |
| App icon, README, screenshots | Assets and docs | Yes |
| GitHub repository, Homebrew tap | Hosting settings | Optional; GitHub redirects old URLs |
| Bundle identifier | `io.github.ghadj.glintboard` (matches today's name by choice and keeps it after any rename), also in `Branding.xcconfig` | Never: macOS ties granted permissions, preferences, and the default data folder to it |
| Default data folder | `~/Library/Application Support/<bundle id>/Library` | Never |
| Xcode project, target, scheme, app module | `App.xcodeproj`, target and scheme `App`, `PRODUCT_MODULE_NAME = App` so tests use `@testable import App` | Never |
| Package and modules | `ScrapKit`: `ScrapModel`, `ScrapStorage`, `ScrapCapture`, `ScrapTestSupport` | Never |
| Log and signpost subsystem | `Bundle.main.bundleIdentifier` | Never |
| File formats | `.collection.json`, `.index.sqlite`, frontmatter keys | Never |

**Rules**

- Swift code never contains the product name as a literal. User-facing text interpolates `AppInfo.displayName`; String Catalog entries use a placeholder for it.
- `Info.plist` privacy strings either avoid the name or use `$(PRODUCT_NAME)`, which Xcode expands at build time.
- There is no `InfoPlist.xcstrings` for now. When one exists, Xcode copies `CFBundleName` and `CFBundleDisplayName` into it with the product name on every IDE build, which breaks the branding check and overrides the Dev build's name at runtime. Info.plist strings stay English-only until a second language is added; that needs its own decision.
- `scripts/check-branding.sh` runs in CI and fails if the display name appears anywhere in `App/` or `Packages/` outside `Config/Branding.xcconfig`.
- "Scrap" is the domain word for the modules because it won't change with the brand, and the prefix avoids a module sharing a name with one of its own types.
- Debug builds append `.dev` to the bundle identifier and "Dev" to the display name (in `Config/Debug.xcconfig`), so a contributor's dev build never shares data, preferences, or permissions with an installed release.

**Rename checklist**: change `APP_DISPLAY_NAME`, replace the icon and docs, optionally rename the repository and tap. Nothing in code or data moves.

## Decisions and risks

The structural choices above become decision records in M0, so the reasoning lives next to the code; the risks below are the ones most likely to force a change to this plan.

**Decision records to write in M0**

| No. | Decision |
| --- | --- |
| 0001 | Native only: Apple frameworks, no third-party packages or build tools |
| 0002 | Markdown files are the source of truth; the index is a rebuildable cache |
| 0003 | Collections are folders; ids live in frontmatter, never in file names |
| 0004 | Reference health lives in the index; background work never writes scrap files |
| 0005 | Fractional ranks for board order |
| 0006 | Three-target package with enforced layering (target dependencies plus `check-layering.sh`) and a test-support target |
| 0007 | Apple Events and Accessibility on a dedicated serial actor with hard timeouts |
| 0008 | AppKit for windows and focus, SwiftUI for content, NSCollectionView for the board |
| 0009 | Composition root with initializer injection; no singletons |
| 0010 | Brand-neutral code, modules, bundle identifier, and data folder; the product name lives only in Branding.xcconfig |
| 0011 | AI readiness in schema 1: derivedFrom and aiExcluded keys reserved, captured text immutable, file text snapshots at capture |
| 0012 | One LibraryQuery tool set behind the Ask panel, the MCP helper, and App Intents; AI output only proposes changes |

**Risks**

| Risk | Impact | Early signal | Mitigation |
| --- | --- | --- | --- |
| Idle memory target too tight for a SwiftUI host | NFR-2 fails late | M0 baseline above 30 MB | Load SwiftUI only when the shelf opens; revisit the target in M0 |
| No clean native way to send Apple Events with a hard timeout off the main thread | Providers block or need workarounds | Spike S2-0 | Dedicated actor plus a racing timeout in the async wrapper |
| Non-activating panel can't take keyboard focus reliably on some macOS versions | Search, notes, and arrow keys break | M1 manual checks | Make the panel key explicitly; fall back to briefly activating the app for note editing |
| Safari private windows undetectable | Privacy promise unclear | Spike S2-1 | Explicit setting and onboarding note |
| Hand-written YAML codec rejects files edited in other tools | Problems list grows | Fixture tests with Obsidian-edited files | Widen the subset deliberately, with tests, never silently |
| macOS re-prompts for Screen Recording | Screenshot feature feels nagging | Beta testers | Mention in onboarding; keep screenshots optional |
| On-device model context is small | Whole-board answers truncate | Retrieval spike in the first AI milestone | Retrieve passages instead of whole boards; staged summaries; cloud backend as opt-in fallback |
| Prompt injection through captured web text | Misleading answers or unwanted actions | Red-team fixtures in the retrieval tests | Scrap text passed as delimited data; validated citations; AI output only proposes, the user confirms |
