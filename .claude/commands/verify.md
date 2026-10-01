---
description: Check a milestone against its definition of done and prepare the PR checklist.
argument-hint: <milestone id, e.g. M1>
---

Verify milestone $ARGUMENTS of Glintboard against `docs/milestones.md`. Don't change code; report only.

1. Run `make check` and `make test SWIFT_TEST_FLAGS=--disable-sandbox` and report each step (lint, native-only, branding, core tests, app tests, build warnings).
2. For every requirement in $ARGUMENTS, find its commit (`git log --grep "<id>:"`) and confirm each automated acceptance criterion has a passing test. List any requirement with no commit or an uncovered criterion.
3. Check that `docs/design.md` and `docs/decisions/` reflect any behavior changes made during the milestone.
4. Produce a report with:
   - A table: check, result (pass or fail), and details for failures.
   - Requirements that look incomplete, with the reason.
   - The milestone's Manual acceptance criteria and the NFR measurements it requires, as a Markdown checklist ready to paste into the PR description, with one line on how to perform each check.
