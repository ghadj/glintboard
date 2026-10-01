---
description: Plan a milestone into docs/plans/<id>.md for human review. Writes no code.
argument-hint: <milestone id, e.g. M1>
---

Plan milestone $ARGUMENTS of Glintboard. Do not write or change any code; the only file you create or edit is `docs/plans/$ARGUMENTS.md`.

1. Read `AGENTS.md`, `docs/design.md`, the $ARGUMENTS section and "Executing with Claude Code" in `docs/milestones.md`, and everything in `docs/decisions/`. Look at the current code to see what already exists.
2. Write `docs/plans/$ARGUMENTS.md` with these sections:
   - **Summary**: two or three sentences on what the milestone delivers.
   - **Order of work**: requirements in implementation order, each with its track (Core or App) and a one-line reason when the order isn't obvious.
   - **Per requirement**: files to create or change, the main types and functions, and for each automated acceptance criterion the test file and test name that will cover it.
   - **Parallel tracks**: which requirements can run in a separate worktree, and the branch names to use.
   - **Spikes**: each spike's question, how you'll answer it, and the decision note it produces.
   - **Things only I can do**: manual steps (for example creating the Xcode project, granting permissions, measurements).
   - **Risks and questions**: ambiguities, likely concurrency or AppKit trouble spots, anything touching the "ask first" list. Number the questions.
   - **Manual checks**: every Manual acceptance criterion as a checklist for the PR.
3. Stop and ask me to review the plan. Don't start implementing until I approve it.
