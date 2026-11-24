---
description: Run the approved task package by package with worker subagents, one at a time. Stops before /gate
argument-hint: [task-dir-name, default is the one in tasks/.active]
---

Run the work packages of task: $ARGUMENTS (if empty, use the directory named in `tasks/.active`).

Let `T` be that task directory under `tasks/`. Read `T/contract.md`. Stop and say so if:
- its status is not `APPROVED` or `T/APPROVED` does not exist (the human approves with `./scripts/approve.sh`);
- its ```scope block is empty or missing: the task has no work packages, so it is done directly, without `/work`.

You are the orchestrator. In this command you do not write or edit project code yourself: workers do. You write only under `T/`.

1. **Plan.** List the packages in the order of the ```scope block. For each: its id, its globs, what it depends on (from the notes under "Work packages"). A package whose note `T/packages/<id>.md` starts with `status: DONE` is finished: skip it. This is how an interrupted `/work` resumes.
2. **For each remaining package, in order, one at a time:**
   1. Write the package id, and nothing else, into `T/.package`. From this moment the hook opens only that package's globs.
   2. Launch the `worker` subagent (Agent tool, subagent_type `worker`). Give it only this: the task directory `T`, the package id, and the paths `T/contract.md`, `T/state.md`, `T/packages/`. Do not summarize the contract for it and do not tell it how to implement anything.
   3. When it returns, read `T/packages/<id>.md`. If the file is missing, or its first line is not `status: DONE`: stop the loop, go to step 5.
   4. Run the check the contract names for this package; if it names none, `./scripts/check.sh`. If it fails on something this package owns, launch a new `worker` for the same package once, giving it additionally the path of the failing log. Each relaunch counts against `budgets.max_repair_attempts` in `harness.yml`. Still failing: stop the loop, go to step 5.
   5. Add one line per finished package to `T/state.md` under PROGRESS (package id, DONE, the check result) and copy its "Decisions" lines to DECISIONS. Then take the next package.
3. **After the last package:** write an empty line into `T/.package` (the whole approved scope is open again), run `./scripts/check.sh`, and record the result in `T/state.md`.
4. **Evidence pass.** A note that says DONE is a worker's claim. Before you call the task ready, go through EVERY acceptance item of the contract, one by one, and find the proof the contract names for it: the test name in a log, the `# red run` section, the raw output of a named command, the measure in `state.md`. Use Grep on the logs; do not rely on the notes. Write the result into `T/state.md` as a list: item, where the proof is (file and line), or MISSING. For a MISSING proof that is only a command to run and log (a `git diff --stat`, a `git status`, a targeted test run, a measure), run it now and log it the way the contract says. For anything else (a red run that needs a code change, a behavior that differs from a decision in the contract), do not repair it yourself and do not launch a worker on your own wording: it goes to the human in step 5. Also read every note's "Decisions": a decision that changes what the contract decided is a deviation and goes to the human, whatever status the note has.
5. **Stop.** Tell the human, in a few lines: which packages are DONE, which one stopped and what it is blocked on (quote its "Blocked on" lines), the result of the last check. List every MISSING proof and every deviation from the evidence pass. Say that the task is ready for `/gate` only if every package is DONE, the check has no FAIL, no proof is MISSING and no deviation is open. Do not start `/gate` yourself.

Rules:
- One worker at a time. Never launch two workers in the same message.
- A worker that reports BLOCKED on a file outside its package is not a failure to work around: it is a question for the human. Do not edit that file yourself, do not change `T/.package` to another package to get it written, and do not ask for a quick approval on the worker's behalf without saying exactly which file and why.
- Do not edit a worker's note. If it is wrong, say so in `T/state.md`.
- The critic in `/gate` reviews the whole change. Package notes are the workers' claims, not evidence.
