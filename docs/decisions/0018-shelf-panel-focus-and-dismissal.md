# 0018: Shelf panel focus and dismissal

- **Date:** 2026-10-04
- **Status:** accepted
- **Requirements:** M1-R15, M1-R16, M1-R18

## Context

The shelf has to take the keyboard (arrow keys now, search and notes later) without activating the app, so the app you're copying from keeps the menu bar. The architecture lists uneven keyboard behavior in non-activating panels as a risk. The M1 plan (Q13) approved closing the shelf on a mouse-up outside it when no drag had started, so a drag from another app wouldn't close it. Spike S1-1 tested both on macOS 27.0.1, with a minimal panel on a throwaway branch (`spike/s1-1`), in three rounds run by the project owner on 2026-10-04. The findings below come from the spike's event log, which was read after each round (each launch rewrote it), and from the owner's reports.

What the spike found:
- **Focus works.** With the panel key, the previous app stayed frontmost and kept the menu bar (`NSWorkspace.menuBarOwningApplication`). `NSApp.isActive` reads true while the panel is key, so it can't tell whether the app was activated.
- **Keys work.** SwiftUI's `.focused` put the `List` in focus when the panel opened, and ↑ and ↓ moved the selection. Esc reached the panel's `cancelOperation(_:)` from the list and from a text field.
- **The Q13 rule fails.** To drag text from TextEdit you first select it, and selecting is a press and release in TextEdit with no drag, so the rule closed the shelf before the drag could start. Nothing seen from outside separates selecting from clicking.
- **Spaces.** `.moveToActiveSpace` left the panel behind on the old Space. `.canJoinAllSpaces` with `.fullScreenAuxiliary` showed it over a full-screen TextEdit.
- **Drops.** The `NSHostingView` registers no drag types, so an AppKit view behind it received drops from TextEdit (RTF and plain text).

## Decision

**Panel:**
- An `NSPanel` with `[.nonactivatingPanel, .titled, .resizable, .fullSizeContentView]`, set at creation. The title bar is transparent, its title and buttons hidden.
- The system draws the frame, corners and shadow, and handles edge resizing, instead of a borderless panel with drawn 12 pt corners. The project owner asked for a look and feel as close to native as possible. The content is an `NSVisualEffectView` with the popover material, always drawn active, as in the spike: under the dismissal rule below, the shelf usually isn't key while you work in the app it opened over. The owner chose this over a material that turns plain when the panel isn't key.
- `.floating` level; `canBecomeKey` true, `canBecomeMain` false, `hidesOnDeactivate` false.
- Collection behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`.

**Focus:**
- `show()` calls `makeKeyAndOrderFront` and never activates the app.
- The shelf's content puts its list in focus with SwiftUI's `.focused`.
- Esc is handled in the panel's `cancelOperation(_:)`.

**Dismissal** (replaces Q13; chosen by the project owner after round 2):
- The shelf closes on Esc, on choosing Show Shelf while it's open, or when an app other than the one it was opened over becomes active (`NSWorkspace.didActivateApplicationNotification`).
- It never closes because it lost key status, and there are no mouse monitors.
- Clicking and selecting in the app you came from leaves it open, so you can select text there and drag it in. Round 3 confirmed this with four drops from TextEdit.

**Drops:** an AppKit view behind the hosting view handles them (M1-R18), as the plan proposed.

## Consequences

- The design doc's window behavior and corner radius change to match (`docs/design.md`, "Window behavior" and "Sizes and spacing"). So do M1-R16's wording in `docs/milestones.md`, `ShelfPanelController` in `docs/architecture.md`, and the plan's R16 section, Q13 and manual check.
- Clicking the desktop is expected not to close a shelf opened over Finder, because Finder stays active; Esc or Show Shelf closes it. Not observed in the spike, so it's part of R16's manual check.
- Switching Spaces usually closes the shelf, because another app becomes active on the new Space.
- Tests can't use `NSApp.isActive` to check that showing the shelf doesn't activate the app. The menu bar owner changes only after the check would run: a stub that activated the app still passed such a test in M1-R15's red run, so that test was dropped, with the owner's approval. The style-mask test and the manual focus check cover it.
- The app has no main menu, so Edit key equivalents (⌘C, ⌘V) may not work in the shelf's text fields. The spike didn't confirm it either way. Check when search and notes arrive.
