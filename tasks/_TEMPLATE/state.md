# State: __TITLE__

<!-- Durable state for this task. Update at every milestone. Raw history is not memory; this file is. -->

## BASELINE
<!-- Filled by /task BEFORE any edit. Paste the raw output, do not summarize. The critic uses it to tell pre-existing changes from this task's changes. -->
- `git rev-parse --short HEAD`:
- `git status --porcelain` (raw):
```
```

## FACTS
<!-- Stable things discovered about the environment. -->
-

## DECISIONS
<!-- Choice and reason. "Reused X because Y." -->
-

## PROGRESS
- completed:
- active:
- blocked:
- remaining:

## CONTRACT CHANGES
<!-- The contract is frozen after approval. If a proof the contract requires (a named test, a case, a check) cannot be
done as written, or you want to move it (for example from a unit test to a manual item), do NOT move it quietly:
write here the item, what the contract says, what you propose, and ask the human. Record his words and the date.
A proof that is moved, weakened or dropped without an entry with the human's words is UNMET for the critic.
"none" if nothing changed. -->
- none

## MANUAL ACCEPTANCE
<!-- Delete if the contract has no manual acceptance. Filled from the human's words, never guessed.
Before /gate every field below has a real value. A template placeholder such as <VERSION> counts as empty:
do not start the critic, ask the human first.
Order before the critic: write the field, then check it is in the file (`grep` the value), then start the critic in a
LATER step, never in the same response as the edit (the edit can fail and the critic reads the old file).
The last pass is on the final build: ANY code change after a pass means a full re-pass of every item on the new build,
unless the human says in words which items he accepts from the old build (show him the list of what changed first).
Say how the product was started (from the IDE with a debugger, or the way a user starts it): the two can behave differently. -->
- build given to the human (`work=` from the last `# check run` line of checks.log):
- device or environment, version, how it was started, date:
- result per item: (one line per item M1, M2, ... with the human's own words. A blanket phrase like "all passed" does not
  fill this field: ask him per item, then write it.)

## ATTEMPTS
<!-- One entry per repair attempt after a failed check or REJECT. Read this section before every new attempt: a dead end listed here is not tried again.
- attempt <N> (<check step, or critic round>)
  - EXPECTED: what the contract or the check wanted
  - SAW: what happened instead (test name, file:line, the blocker as the critic wrote it)
  - FENCE: the files this attempt may touch; nothing outside
  - DEAD ENDS: what was tried and did not work, one line each
The same SAW again (`budgets.max_unchanged_failures` in harness.yml) means stop and ask the human. -->
-

## LESSONS
<!-- Failures that should change future behavior. Candidates for /retro. -->
-
