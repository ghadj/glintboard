# 0012: One LibraryQuery tool set behind every AI surface; AI output only proposes

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M8-R7, M9-R1, M9-R2

## Context

Three surfaces will query the library with AI: the Ask panel, a read-only MCP helper for external agents, and App Intents for Shortcuts and Spotlight. Separate query code per surface would drift. Captured web text can also carry prompt injection.

## Decision

- One `LibraryQuery` tool set (`search`, `getScrap`, `getBoard`, `getBoardContext`) in `ScrapRetrieval` serves all three surfaces. The MCP helper opens the index read-only and never writes.
- AI output can only propose changes (new scraps, titles, moves) that the user confirms; nothing writes files on a model's say-so. Scrap text is always passed to models as delimited data, and citations are validated against the current text.
- AI is off by default and prefers on-device processing; a cloud backend needs an explicit setting and key, and excluded scraps and collections are skipped everywhere.

## Consequences

- The network rule becomes "no network except opt-in web checks and an opt-in cloud AI backend".
- New AI surfaces reuse the tool set instead of adding query paths.
