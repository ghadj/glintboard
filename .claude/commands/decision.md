---
description: Record a design decision or spike outcome in docs/decisions/.
argument-hint: <short title>
---

Record a decision titled "$ARGUMENTS".

1. Find the highest-numbered file in `docs/decisions/` and use the next number, zero-padded to four digits. Name the file `NNNN-<kebab-case-title>.md`.
2. Fill in `docs/decisions/0000-template.md`: today's date, status `accepted` (or `proposed` if I haven't confirmed it), the affected requirement IDs, and short Context, Decision, and Consequences sections based on our conversation and the code.
3. Add a one-line entry to the "Decision log" at the end of `docs/milestones.md`.
4. If the decision changes behavior described in `docs/design.md`, update the design doc to match and mention it in Consequences.
5. Show me the new file's path and a one-sentence summary. Don't commit unless I ask.
