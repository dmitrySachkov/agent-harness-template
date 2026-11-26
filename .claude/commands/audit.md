---
description: Harness audit: which blocker classes repeat, and what each harness rule caught since the last audit
argument-hint: [--since YYYY-MM-DD, optional]
---

A periodic look at the harness itself, not at one failure (that is `/retro`). Run it every ten tasks or so, or when the human asks. It changes nothing except one report file. Arguments: $ARGUMENTS

1. Run `./scripts/verdicts.sh $ARGUMENTS` and read the whole output. If `docs/` has an earlier `harness-audit-*.md`, read the latest one too, and use its date as `--since` when no argument was given.
2. **Blocker classes.** Group the blocker lines by cause, not by task. Use only what the lines say: do not read code, do not guess. For each class: a name, the count, the tasks, one example with its task and round. A class is real when it has blockers from at least two tasks; put the rest under "single cases".
3. **One rule per repeating class.** For each real class propose ONE change, as far down this ladder as practical: enforced policy (hook / deny rule) > automated check (a script step, a test, a rules line) > template field > checklist item > explanation. Word it as a general rule, not as the story of one task. If the class is already covered by a rule that exists, say which rule and why it did not hold.
4. **What each rule caught.** For every rule the output shows evidence for (the hook's block rules from HOOK BLOCKS; the PROBLEM kinds of `scripts/evidence.sh` if they appear in `checks.log` or `state.md` of the period; steps of `/gate` named in the blockers) write what it caught in the period: a count, or "nothing". A rule with "nothing" in this audit AND in the previous one is a candidate for removal. Hard stops (deploy, release, migration, approval files) are never candidates: their value is not in how often they fire.
5. Write `docs/harness-audit-<YYYY-MM-DD>.md`: the totals line, the classes, the proposed rules, the "what each rule caught" table, the removal candidates. Mark every statement you could not verify from the output as NOT VERIFIED.
6. Stop. Apply nothing: hooks, `harness.yml`, `scripts/approve.sh` and the critic are the human's, and the human decides which proposals become work (each one through `/task` or a quick approval).
