@AGENTS.md

# Claude Code specifics

Everything in `AGENTS.md` applies. These notes cover what only Claude Code has.

## Sandbox

The project enables Claude Code's sandbox (`.claude/settings.json`). Inside it:

- Run core tests as `make test-core SWIFT_TEST_FLAGS=--disable-sandbox`. SwiftPM sandboxes its own manifest builds, and macOS doesn't allow one sandbox inside another; the outer sandbox still applies.
- `make run` and `open` need approval and run outside the sandbox, because the sandbox blocks Apple Events.
- Personal overrides go in `.claude/settings.local.json` (gitignored), never in the shared settings.

## Workflow commands

- `/milestone M1`: write `docs/plans/M1.md` and stop for review.
- `/req M1-R6`: implement one requirement test-first, run the `reviewer` subagent, and commit.
- `/verify M1`: check the definition of done and produce the PR checklist.
- `/decision <title>`: record a decision in `docs/decisions/`.

## Hooks

- After each edit, Swift files are formatted automatically.
- When you try to finish with changed Swift files, core tests run; failures are sent back to you to fix.

Use the `reviewer` subagent on every requirement's diff before committing.
