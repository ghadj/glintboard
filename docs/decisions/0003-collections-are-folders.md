# 0003: Collections are folders; ids live in frontmatter, never in file names

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M1-R5, M1-R10, M4-R1, M4-R2

## Context

Users and other tools may rename, move, or copy files. If a scrap's collection or identity were encoded in both the file and its location, the two could disagree.

## Decision

- A collection is a folder under the library root. Scrap files never store their collection; moving a file between folders moves the scrap.
- The `id` in frontmatter is authoritative. Ids are never parsed from file names, which are only for humans: `<yyyy-MM-dd-HHmm>-<first 4 hex of id>.md`, with a numeric suffix on collisions.
- When two files share an id (usually a Finder copy), reconciliation keeps the id on the older path and gives the newer file a fresh id. It's the one case where the app rewrites a file it didn't just save, and it's logged.

## Consequences

- Moving a scrap is a file rename; no frontmatter change is needed.
- Collection settings live in `.collection.json` inside the folder, with the same lazy-migration rule as scrap files.
