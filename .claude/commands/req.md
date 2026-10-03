---
description: Implement one requirement test-first, review it, and commit it.
argument-hint: <requirement id, e.g. M1-R6>
---

Implement requirement $ARGUMENTS of Glintboard.

1. Read the requirement and its milestone's acceptance criteria in `docs/milestones.md`, and the matching entry in `docs/plans/<milestone>.md`. If the plan doesn't exist or hasn't been approved, stop and say so.
2. If the requirement has automated acceptance criteria in `ScrapKit`, write those tests first and have them run (see step 4) to confirm they fail for the right reason.
3. Implement the requirement, following `AGENTS.md`. Keep the change limited to this requirement.
4. Get the tests run. Claude Code's sandbox blocks `swift test` and `xcodebuild`, so ask me to run `make test-core` (Core changes) or `make test` (App changes) in Terminal and say "done"; then read `.build/logs/summary.md`, and the full log in `.build/logs/` only if something failed. Don't ask me to paste output. Batch requests: one run per round of changes.
5. Run `make check` yourself (it works in the sandbox) and fix any issues.
6. Before the review, check your own work:
   - For each new or changed test, say how it fails without your change, and prove it where you can (run it before the implementation, or seed the violation it guards against). A test that compares a value with itself, or reads the same source as the code under test, doesn't count.
   - For each statement you added to a doc or decision record, point to its source (the plan, `docs/design.md`, `docs/architecture.md`, `docs/milestones.md`, or my answers). Remove anything you can't source.
7. Ask the `reviewer` subagent to review the diff for $ARGUMENTS, saying which test results you already have. Fix every Blocking finding, then get the tests re-run (step 4). If you disagree with a finding, explain why instead of ignoring it.
8. If the behavior differs from `docs/design.md`, update the design doc and record the decision as described in `.claude/commands/decision.md`.
9. If you or I built in the Xcode app, check `git status` for files Xcode changed on its own (see `AGENTS.md`) before committing.
10. Commit with the message `$ARGUMENTS: <short summary>`. Don't push.
11. Finish with a short summary: what changed, tests added, any reviewer findings you deferred, and **Manual checks remaining** for me.

If you hit anything on the "Ask before doing any of these" list in `AGENTS.md`, stop and ask.
