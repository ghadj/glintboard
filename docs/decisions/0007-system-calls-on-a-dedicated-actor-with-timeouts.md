# 0007: Apple Events and Accessibility on a dedicated serial actor with hard timeouts

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M2-R1, M2-R2, M2-R3

## Context

Apple Events and Accessibility calls are synchronous IPC into other apps. A hung or slow Safari or Mail would block whatever thread makes the call, and the default Apple Event timeout is about two minutes. Running these calls on the main actor freezes the UI; running them on Swift's cooperative pool can starve it.

## Decision

- Every Apple Event and Accessibility call runs on one dedicated actor whose executor is its own `DispatchSerialQueue`, never the main actor or the cooperative pool.
- Every call has an explicit short timeout (250 ms by default): Apple Events always pass an explicit timeout, Accessibility sets `AXUIElementSetMessagingTimeout`, and the async wrapper also races a `Task.sleep` so the caller is released even if the system call ignores its timeout.
- Capture saves the scrap with a fallback reference first; the claiming provider's result replaces it only if it arrives in time.

## Consequences

- A hung target app costs a fallback reference, never a frozen UI or a lost capture.
- Permission state is checked without prompting (`AEDeterminePermissionToAutomateTarget`); denials degrade to the fallback with one banner.
- Spike S2-0 settles the exact Apple Event sending mechanism.
