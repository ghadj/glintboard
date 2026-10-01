# Contributing

Thanks for helping. Glintboard is a native macOS app with no third-party dependencies, so setup is short.

## Setup

You need a Mac that can run the Xcode version in `.xcode-version` (Xcode installs everything else, including Swift and swift-format). No Homebrew packages, containers, or version managers are required.

```bash
git clone <repo-url> && cd <repo>
make bootstrap   # checks Xcode, creates Config/Local.xcconfig, runs core tests
make run         # builds and launches the Dev app
```

You can also open `App.xcodeproj` in Xcode and run the `App` scheme.

**Signing (optional but recommended).** Put your Team ID in `Config/Local.xcconfig` (a free Apple ID works; find it in Xcode > Settings > Accounts). Without it, builds are signed ad hoc and macOS forgets the permissions you grant every time you rebuild.

**Your data is safe.** Debug builds are a separate app, "Glintboard Dev", with its own bundle id, data folder, and permissions. They never touch an installed release. To try permission prompts again: `tccutil reset All <bundle id>.dev`. To work with realistic data, generate a test library with `scripts/seed-library`.

## Everyday commands

`make help` lists everything. The common ones: `make test-core` (fast, run constantly), `make test`, `make format`, and `make check` (what CI checks besides tests).

## How work is organized

- `docs/design.md` describes what the app does, `docs/architecture.md` how it's built, and `docs/milestones.md` what's next, with requirement IDs like `M2-R6`.
- Pick an open issue (look for `good first issue` or `provider`), or open one before starting anything large.
- Branch names: `m2-r6-text-fragments` for requirement work, `fix/<short-description>` for bugs.
- One requirement or fix per pull request where possible. Fill in the PR template, including the manual checks for anything the tests can't cover.
- Design changes need an update to `docs/design.md` and a decision record in `docs/decisions/` (copy `0000-template.md`).

## Ground rules

- **Native only.** Apple frameworks only; no Swift packages or vendored code. CI enforces this.
- **Brand-neutral code.** Never write the product name in code; use `AppInfo.displayName`. CI enforces this too.
- **Privacy first.** Never log captured content except as private, never add network calls outside the documented opt-in features, and never store concealed or transient pasteboard items.
- **Tests with fakes.** Logic lives in `Packages/ScrapKit` and is tested with the fakes in `ScrapTestSupport`; system access goes through protocols.

`AGENTS.md` summarizes the architecture rules in one page; it's written for AI coding agents but works as a checklist for anyone.

## Using AI coding agents

Welcome, with the same standards as any other contribution: you're responsible for every line, tests must cover the change, and the PR description should say what you verified by hand. The repo includes shared Claude Code settings, commands, and a reviewer agent (`.claude/`); other agents read `AGENTS.md`.

## Reporting bugs and security issues

Use the issue templates for bugs and provider requests. For anything that could expose users' data, follow `SECURITY.md` instead of opening a public issue.
