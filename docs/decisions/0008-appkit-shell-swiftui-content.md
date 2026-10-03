# 0008: AppKit for windows and focus, SwiftUI for content, NSCollectionView for the board

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M0-R9, M1-R15, M1-R17, M5-R1, M5-R2

## Context

The shelf must take keyboard focus without activating the app (so the previous app stays frontmost), and the board must stay within the memory budget at 500 images. SwiftUI can't express a non-activating key panel, and a SwiftUI `Layout` creates every card up front.

## Decision

- AppKit owns windows, focus, and anything performance-sensitive: the status item (`MenuBarController`), the non-activating `NSPanel` shelf, and one window per board.
- SwiftUI draws content inside them: the shelf list (a lazy `List` in an `NSHostingView`), cards, reference cards, and the note editor.
- The board is an `NSCollectionView` with a custom masonry layout, whose math lives in Core, so item views are reused and memory returns when the window closes.

## Consequences

- The app uses an AppKit lifecycle (`@main` with `NSApplication` and an app delegate), not a SwiftUI `App`.
- Panel activation, key-window, and focus behavior is on the "ask first" list in `AGENTS.md`.
