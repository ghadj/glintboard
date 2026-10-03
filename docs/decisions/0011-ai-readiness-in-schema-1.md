# 0011: AI readiness in schema 1

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M1-R1, M1-R20, M2-R10, M4-R1

## Context

AI features (semantic search, cited answers, board-level context) are planned after 0.1 (M7–M9). Three of the gaps they need would change the file format or what gets captured, so they must close before the first release even though the AI features ship later.

## Decision

- Schema 1 reserves two frontmatter keys: `derivedFrom` (a list of scrap ids) and `aiExcluded` (a boolean, also settable for a whole collection in `.collection.json`).
- Captured text is immutable: no store API changes a scrap's body after capture; corrections go in the note. An external edit changes the content hash, which marks existing citations stale instead of silently wrong.
- At capture, the Files provider stores a text snapshot of the file (up to 1 MB) in the collection's `assets/`, so the content survives if the source file is deleted.

## Consequences

- The AI milestones add targets (`ScrapRetrieval` in M7-R1, `ScrapAssist`) and index tables without a file-format change.
- With AI off, nothing AI-related is built or loaded, and the resource budget is unchanged.
