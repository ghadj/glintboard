# 0005: Fractional ranks for board order

- **Date:** 2026-10-01
- **Status:** accepted
- **Requirements:** M1-R4, M5-R2

## Context

Boards are ordered by hand, and moving a card should rewrite only that card's file (`docs/design.md`, the `board` key in the data model).

## Decision

Board order is a fractional `Rank`, stored as a string in each scrap's `board` frontmatter key. `Rank.between(a, b)`, `Rank.after(a)`, and `Rank.before(b)` produce a key that sorts between its neighbours, so any reorder writes exactly one file.

## Consequences

- The board re-flows from the in-memory order after a move; no other scrap is touched.
