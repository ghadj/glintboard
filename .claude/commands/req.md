---
description: Implement one requirement test-first, review it, and commit it.
argument-hint: <requirement id, e.g. M1-R6>
---

Implement requirement $ARGUMENTS of Glintboard.

1. Read the requirement and its milestone's acceptance criteria in `docs/milestones.md`, and the matching entry in `docs/plans/<milestone>.md`. If the plan doesn't exist or hasn't been approved, stop and say so.
2. If the requirement has automated acceptance criteria in `ScrapKit`, write those tests first and run them to confirm they fail for the right reason.
3. Implement the requirement, following `AGENTS.md`. Keep the change limited to this requirement.
4. Run `make test-core SWIFT_TEST_FLAGS=--disable-sandbox`. If App code changed, also run `make build`.
5. Run `make check` and fix any issues.
6. Ask the `reviewer` subagent to review the diff for $ARGUMENTS. Fix every Blocking finding, then re-run tests. If you disagree with a finding, explain why instead of ignoring it.
7. If the behavior differs from `docs/design.md`, update the design doc and record the decision as described in `.claude/commands/decision.md`.
8. Commit with the message `$ARGUMENTS: <short summary>`. Don't push.
9. Finish with a short summary: what changed, tests added, any reviewer findings you deferred, and **Manual checks remaining** for me.

If you hit anything on the "Ask before doing any of these" list in `AGENTS.md`, stop and ask.
