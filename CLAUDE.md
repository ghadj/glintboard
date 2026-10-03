@AGENTS.md

# Claude Code specifics

Everything in `AGENTS.md` applies. These notes cover what only Claude Code has.

## Sandbox

The project enables Claude Code's sandbox (`.claude/settings.json`). Inside it:

- Don't build or run tests yourself: `swift test` and `xcodebuild` write to the per-user temp and cache folders under `/var/folders`, which the sandbox blocks (`xcrun swift-format` still works). Ask the user to run the `make` target in Terminal (commands run with `!` can be sandboxed too) and say "done", then read `.build/logs/summary.md`, and the full log in `.build/logs/<target>.log` if something failed. Don't ask the user to paste output. Don't propose changes to the sandbox settings (decision 0014). `make check` (lint and the native-only, branding, and layering checks) works inside the sandbox.
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
