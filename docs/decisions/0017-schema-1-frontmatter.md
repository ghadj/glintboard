# 0017: Schema 1 frontmatter: keys, writing rules, and the YAML subset

- **Date:** 2026-10-04
- **Status:** accepted
- **Requirements:** M1-R1, M1-R2, M1-R4, M1-R7, M1-R12

## Context

Scrap files are the source of truth (0002), and other tools such as Obsidian edit them. `docs/design.md` gives one example file, but not every key, how optional values are written, or how much YAML the reader accepts. Changing the schema later needs a version bump and a migration (`AGENTS.md`), so schema 1 has to be settled before the first file is written. The project owner answered the open points while reviewing the M1 plan (questions Q1 and Q2, 2026-10-03) and during M1-R2 (quoting, 2026-10-04).

## Decision

**Keys** (written in this order):
- **Top level:** `schema`, `id`, `kind`, `title`, `pinned`, `board`, `created`, `updated`, `reference`, `asset`, `note`, `noteUpdated`, `derivedFrom`, `aiExcluded`.
- **Inside `reference`:** `provider`, `app`, `window`, `locator`, `bookmark`, `deepLink`, `label`, `fingerprint`.
- **Unknown top-level keys** come last, in their original order, and are kept on every rewrite.
- **Unknown keys inside `reference`** can't be kept, so a file that has one fails to load (`invalidValue`) rather than losing the key on the next save.

**Required keys:**
- `schema`, `id`, `kind`, `board`, `created`, `updated`, and `reference` with its `provider`, `label` and `fingerprint`.
- A known key with no value (`title:`, as an editor may leave an emptied property) counts as absent. A missing `title` reads as empty, a missing `pinned` or `aiExcluded` as false, and a note without `noteUpdated` takes the scrap's `updated`. A plain `null` or `~` on an optional text key also reads as absent.
- A file whose `schema` is newer than the app's is an error, so an older app never rewrites a newer file. The schema line is checked before the rest is parsed, so this is the error reported even when the newer file uses syntax this version can't read.

**File references (Q1):**
- For file scraps, `reference.locator` holds the path and `reference.bookmark` the base64 bookmark.
- The thumbnail, or a stored image, goes in the top-level `asset`.
- The Files provider's handling of dropped files moves into M1 (M1-R12) to write these.

**How locators are read:**
- With a `bookmark`: a file.
- Otherwise, by provider: a Message-ID for `mail`, a rectangle (`x,y,width,height`) for `screenshot`, an absolute URL for `safari`.
- Anything else, including a locator from a provider this version doesn't know, is kept as written.
- No `locator`: the app and window alone (fallback provider).

**Writing rules (Q1, and quoting on 2026-10-04):**
- Every string is double-quoted, `kind` and `provider` included (rule 5 in `AGENTS.md`, with no exceptions). The design doc's example now shows `kind: "text"` and `provider: "safari"`.
- `reference.app` holds the bundle id only; the app's name is looked up when it's shown. It's left out when no external app was known.
- Optional keys with no value are left out. `derivedFrom` and `aiExcluded` are written only when non-empty or true.
- Escapes: quotes, backslashes, line breaks, tabs, control characters, line and paragraph separators, the byte-order mark and the noncharacters U+FFFE and U+FFFF are escaped (`\"`, `\\`, `\n`, `\t`, `\r`, `\uXXXX`).
- Dates are ISO 8601 in UTC, to the whole second.
- The note is a `|` block: chomping `-`, none or `+` keeps its trailing newlines exact, and an indentation indicator (`|2`) is added when its first line starts with a space. It falls back to a double-quoted string when only that keeps it exact: empty or newline-only text, carriage returns, characters that need escaping, or lines holding only whitespace.
- A leading byte-order mark is skipped on read and not written back.

**`.collection.json` (M1-R5, confirmed 2026-10-04):**
- JSON with `schema` (1), `order` (an integer) and `created` (an ISO 8601 UTC date), pretty-printed with sorted keys. Unknown keys are kept with their JSON type.
- A file without `schema` reads as schema 1. A newer schema, or a file that isn't valid, is left alone, and its folder is still listed as a collection, after the others.

**`board` keys (M1-R4):**
- A key is an integer part whose first letter gives its length (`a` plus 1 digit, `b` plus 2, …; `Z` plus 1, `Y` plus 2, … below the `a` keys), followed by a base-62 fraction (`0-9A-Za-z`) that never ends in `0`.
- The exact key `A` followed by 26 zeros is reserved.
- A `board` value that isn't a valid key is an error.

**The YAML subset (Q2):**
- **Read:**
  - `key: value` lines with LF or CRLF line endings (the body is never changed);
  - plain, single-quoted and double-quoted scalars;
  - `|` blocks for any key (read as text);
  - block lists (`- item`) and one-line flow lists (`[a, b]`) of scalars;
  - one level of nested map (`reference`).
- **Keys:** only plain keys the writer can write back unchanged. That rules out a leading indicator character or space, a trailing colon or space, tabs, line breaks or characters that need escaping, and `: ` or ` #` inside. Any other key is a syntax error, so an unknown key is never lost on a rewrite.
- **Rewritten once, the first time the app saves the file:** values written by other tools change to the canonical form (double-quoted strings, block lists, fixed key order).
- **Unknown keys keep their YAML type.** A plain value that YAML reads as something other than text (a number, boolean, null or date, for example Obsidian's `rating: 4.5` or `due: 2026-10-15`) is kept and written exactly as it was, unquoted. A key with no value stays `key:`.
- **Typed errors**, leaving the file untouched:
  - anchors and aliases;
  - YAML type tags (`!!str`), which is what "tags" means in the M1 acceptance criteria, not Obsidian's `tags:` list;
  - flow maps and folded (`>`) scalars;
  - maps inside lists or under unknown keys, and lists inside lists;
  - values continued on another line;
  - comments, directives, and the `...` document marker (a second `---` simply ends the frontmatter);
  - complex or quoted keys;
  - tab indentation.

## Consequences

- Files written by the app are deterministic, and writing a file the app has read gives the same bytes. M1-R2's tests check this on 1,000 generated scraps, and check that the design doc's example is reproduced byte for byte.
- The writer's output always reads back. Values built in code that the reader couldn't read back as written are adjusted instead of producing a broken file: a non-literal `.scalar` is quoted, a list inside a list is written as its text, and an unknown entry whose key isn't a plain key (or repeats or shadows a known key) is left out.
- An Obsidian-edited file loads, and its properties keep their types. It's rewritten into the canonical form only when the app next saves it, for example after a note edit.
- Files using YAML outside the subset fail to load and are logged (and, from M1-R21, listed under Problems). Widening the subset is a deliberate change with fixtures, never a silent one.
- `Locator` gains an `.other` case, so locators the app can't interpret survive a rewrite.
- `docs/design.md`'s scrap-file example quotes `kind` and `provider`. Its Reference table says `app` can be absent and that a file's bookmark sits beside the locator. A paragraph under the example lists the optional keys, `asset` and `bookmark`, and points here.
