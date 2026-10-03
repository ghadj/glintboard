@AGENTS.md

# Claude Code specifics

Everything in `AGENTS.md` applies. These notes cover what only Claude Code has.

## Sandbox

The project enables Claude Code's sandbox (`.claude/settings.json`). Inside it:

- Don't build or run tests yourself: `swift test`, `xcodebuild`, and `xcrun` write to the per-user temp and cache folders under `/var/folders`, which the sandbox blocks. Ask the user to run the command with `!` and read the output, for example `! make test-app 2>&1 | grep -E "error:|warning:|Test case|\*\* TEST"`. Don't propose changes to the sandbox settings (decision 0014). Lint (`xcrun swift-format lint`), `scripts/check-native-only.sh`, and `scripts/check-branding.sh` do work inside the sandbox.
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
