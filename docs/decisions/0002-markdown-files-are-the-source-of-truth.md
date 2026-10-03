# 0002: Markdown files are the source of truth; the index is a rebuildable cache

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M1-R2, M1-R5, M1-R6, M1-R8, M1-R9, M1-R10

## Context

Data safety is the first architecture driver. Users should be able to read, back up, and edit their library with other tools (Obsidian, a text editor) and never lose scraps to a database problem. Search and sorting still need fast queries.

## Decision

Each scrap is a plain Markdown file with YAML-subset frontmatter, and those files are the only source of truth. The SQLite index mirrors them for search and sorting and can always be deleted and rebuilt.

- Writes are atomic: a temporary file in the same folder, then a replace.
- The frontmatter writer is deterministic (fixed key order), always double-quotes strings, and preserves unknown keys.
- Launch reconciliation compares `(path, mtime, size)` with the index and repairs drift in the background.
- A missing, corrupt, or old-schema index (`PRAGMA user_version`) is deleted and rebuilt.

## Consequences

- External edits are first-class: the folder watcher picks them up and the index follows.
- Files that fail to parse are listed under "Problems" and never modified.
- Files migrate to a newer schema lazily, when the user next changes them, never in a bulk rewrite.
- Anything stored only in the index (reference health, embeddings later) must be re-derivable or acceptable to lose.
