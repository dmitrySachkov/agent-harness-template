---
description: Turn a failure into a harness improvement (diagnosis -> one new check, rule, map entry or template change)
argument-hint: [what went wrong, optional]
---

A run failed, was rejected, or needed a human to step in. Do not just fix the output; find what in the system allowed it. Context: $ARGUMENTS

1. Read the active task's `state.md`, `checks.log`, `verdict.md` (if present) and `tasks/lessons.md`.
2. Answer each question with a concrete observation from this run, or "no":
   - Was the task contract ambiguous or missing a constraint?
   - Was important context invisible (not in the map, not in docs)?
   - Was the wrong tool or command used, or a precondition missing?
   - Was the result unverifiable (no check could have caught it)?
   - Was a rule left as prose that should have been enforced?
   - Was recovery too broad (retry without changing anything)?
   - Was the trace insufficient to see what happened?
3. Pick **one** improvement, as far down this ladder as practical (higher = stronger):
   enforced policy (hook / deny rule) > automated check (a test, a `layers.rules` line, a `check.sh` step) > template field > checklist item > explanation in `docs/` or `CLAUDE.md`.
   Prefer the smallest change that would have prevented this exact failure. If the failure is a one-off, say so and change nothing.
4. Append an entry to `tasks/lessons.md` in the format defined at its top.
5. Apply the improvement only if it lives in a file you are allowed to edit (`docs/`, `tasks/_TEMPLATE/`, `CLAUDE.md`, `profiles/`). Hooks, `settings.json`, `harness.yml`, `scripts/approve.sh` and the critic are protected: for those, write the exact proposed change in the lessons entry and ask the human to apply it. `CLAUDE.md` and `profiles/` are behind Gate 1 like project code: if the edit is blocked because no approval is in force, write the proposed change in the lessons entry and ask the human for `./scripts/approve.sh --quick`.
6. Stop. Report the diagnosis and the one change in three sentences.
