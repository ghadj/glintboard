# 0014: Builds and tests are run by the user, not inside Claude Code's sandbox

- **Date:** 2026-10-03
- **Status:** accepted
- **Requirements:** M0-R5, M0 acceptance criteria

## Context

M0 asked that Claude Code, started with the sandbox on, run the build and tests without prompts beyond first-time approvals. In practice `swift test`, `xcodebuild`, and `xcrun` write to the per-user temp and cache folders (`/var/folders/<…>/T` and `/C`, found through `confstr`, not `$TMPDIR`). The sandbox only allows `$TMPDIR`, so every build fails with "Operation not permitted", and `--disable-sandbox` (which only turns off SwiftPM's own manifest sandbox) doesn't help. The only fix would be widening the sandbox in `.claude/settings.json` or `.claude/settings.local.json`, and the project owner doesn't change those settings.

## Decision

The user runs builds and tests (`make test-core`, `make test-app`, `make build`, `make ci`) with `!` in the Claude Code prompt, and Claude reads the output. Claude still runs what works inside the sandbox: lint and the native-only and branding checks. The sandbox settings stay as they are, and Claude doesn't propose changing them.

The M0 acceptance criterion is reworded to match.

## Consequences

- Every requirement takes a round trip through the user for its test run. Claude asks for one combined, filtered command per run to keep that short.
- The stop hook's core-test gate still works, because hooks run outside the sandbox.
- `CLAUDE.md` tells agents not to build or test themselves. The `/req` and `/verify` commands still say "run `make test-core`"; agents read that as "ask the user to run it".
- If a future Claude Code version lets the build tools' temp folders be used inside the sandbox without a settings change, this can be revisited.
