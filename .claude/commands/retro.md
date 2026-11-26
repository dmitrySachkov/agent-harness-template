---
description: Turn a failure into a harness improvement (diagnosis -> one new check, rule, map entry or template change)
argument-hint: [what went wrong, optional]
---

A run failed, was rejected, or needed a human to step in. Do not just fix the output; find what in the system allowed it. Context: $ARGUMENTS

1. Read the active task's `state.md`, `checks.log`, `verdict.md` (if present) and `tasks/lessons.md`.
2. First place the failure with three questions about the failed run. Answer each with a concrete observation, and treat each "no" as the layer to fix:
   - Could the agent see it? The fact it needed was in the contract, the map, `state.md` or a file it was pointed to. No -> contract, map or state.
   - Could it do it? A tool or command for the action existed and was permitted. No -> tools or permissions.
   - Could it tell? A check existed that could have come back red on this mistake. No -> checks or exits.
   If all three are yes and the same failure has repeated, say so plainly: the cause may be the model or the framing of the task, not the harness. Do not invent a harness fix for it.
   Then answer each question below with a concrete observation from this run, or "no":
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
   Word the improvement as a general rule, not as the story of this run: it must name a class of change or situation, not this file, screen or date. Test: would it make sense to someone who was not there, on a different task? If it would not, it is a one-off: say so and change nothing.
4. Append an entry to `tasks/lessons.md` in the format defined at its top. The story of this run goes in `failure`, the general rule in `fix`.
5. Apply the improvement only if it lives in a file you are allowed to edit (`docs/`, `tasks/_TEMPLATE/`, `CLAUDE.md`, `profiles/`). Hooks, `settings.json`, `harness.yml`, `scripts/approve.sh` and the critic are protected: for those, write the exact proposed change in the lessons entry and ask the human to apply it. `CLAUDE.md` and `profiles/` are behind Gate 1 like project code: if the edit is blocked because no approval is in force, write the proposed change in the lessons entry and ask the human for `./scripts/approve.sh --quick`.
6. Stop. Report the diagnosis and the one change in three sentences.
