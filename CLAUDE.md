# __PROJECT__

> Short map + hard rules. Details live in the files below; open them only when the task needs them.
> Do not paste long docs into this file. If a rule matters repeatedly, move it into a check or a hook.

## Map

| What | Where |
|---|---|
| Project settings, check commands, budgets, gates, model, advisor | `harness.yml` (read-only for you) |
| Architecture and layer rules | `docs/architecture.md` |
| Build / test / run commands | `docs/commands.md` |
| Release rules | `docs/release.md` |
| Task contracts, state, receipts | `tasks/<id>/` |
| Lessons from past failures | `tasks/lessons.md` (read before starting a task) |

## Workflow (every non-trivial change)

1. **Contract first.** Work starts with `/task <description>`. It creates `tasks/<id>/contract.md` with status `DRAFT`.
   **Gate 1:** project code is locked by a hook until the human approves the contract with `./scripts/approve.sh` in their own terminal. You cannot run that script or write its files, and "approved" said in chat unlocks nothing. After approval `contract.md` is frozen: if it has to change, write the change in `state.md` and ask the human.
   `/task` ends with a read-only review of the draft by the `contract-reviewer` subagent (advisory: the human still decides).
   **Work packages (optional).** A contract may list packages in a ```scope block. After approval the hook lets project files be edited only inside those globs. Such a task is run with `/work`: one `worker` subagent per package, one at a time, each limited by the hook to its own globs and leaving a note in `tasks/<id>/packages/`. Before the task is called ready for `/gate`, the orchestrator finds the named proof for every acceptance item in the logs. A contract with an empty block is done directly, as before.
2. **Work in small steps.** Keep `tasks/<id>/state.md` current: facts, decisions (with reason), progress, lessons. Update it at every milestone, not at the end.
   If an advisor is configured (`advisor:` in `harness.yml`), consult it before choosing between two approaches and before escalating a repeated failure. Save your work before the consult and record the advice and your decision in `state.md`. The advisor shares this session's context: it does not replace the independent `critic`.
3. **Verify cheaply, then expensively.** `./scripts/check.sh` runs lint -> build -> unit -> arch. `./scripts/check.sh --full` adds UI tests.
4. **Independent critic.** `/gate` runs the full checks, then the `critic` subagent (fresh context, read-only, tries to reject the result).
5. **Receipt.** After `ACCEPT`, `/receipt` writes `tasks/<id>/receipt.md`. The receipt ends the approval: project code is locked again.
   **Gate 2:** stop and hand the receipt to the human. Never commit, merge or push on your own.

Small change without a contract (a typo, a one-line fix): the human runs `./scripts/approve.sh --quick`, which unlocks a few files for an hour. If an edit is blocked by Gate 1, do not look for another way to write the file: say what you need and ask for a contract or a quick approval. Always editable: `tasks/` and `docs/`.

## Definition of done

All of these, with evidence in `tasks/<id>/`:
- every acceptance item in `contract.md` is met and has proof (test name, log line, file:line);
- `check.sh --full` has no FAIL; every SKIP is listed under NOT VERIFIED in the receipt;
- `verdict.md` says `ACCEPT`;
- `receipt.md` exists.

"Done" without evidence is a claim, not a result. Do not say a check passed unless it ran in this session.

## Hard stops (also enforced by hooks, do not try to bypass)

Never run, and never ask the human to run silently on your behalf:
- deploys, store releases (App Store / TestFlight upload), package publishing;
- database or schema migrations, infra apply/destroy;
- anything outside the repo workspace, or touching secrets (`.env*`, keys, tokens).

If the task needs one of these, finish the preparation, write it under APPROVAL NEEDED in the receipt, and stop.

## Loop budgets

- Max repair attempts per failing check: see `budgets.max_repair_attempts` in `harness.yml`.
- A retry must change something relevant (code, input, assumption). The same failure twice in a row: consult the advisor once if one is configured, and if that does not help, stop and escalate.
- More files changed than `budgets.max_files_changed`, or the scope grows beyond the contract: stop and ask.
- Contradictory requirements, missing permission, or an ambiguous contract: ask, do not guess.

## Working rules

- Stay inside the contract's scope. Anything in "must not change" is untouchable.
- Never weaken a test (delete, skip, loosen an assertion) to make a check pass. Fix the cause, or report it.
- Do not edit generated files or paths listed under `protected_paths` in `harness.yml`.
- Prefer reuse of existing code and patterns over new abstractions. Record real decisions in `state.md`.
- When something fails for a reason the harness could have prevented, run `/retro` instead of just fixing the output.
- For broad searches across many files, use the `Explore` subagent (cheap, read-only) instead of reading files one by one in the main session.
- The model is set in `harness.yml` (`model:`) and the advisor next to it (`advisor:`), with an optional per-task model override in the contract. You cannot switch either, and this file does not select them. If the session starts with a MODEL MISMATCH message, tell the human in your first reply and do not start work until they switch or confirm. An ADVISOR DRIFT message means `harness.yml` and `.claude/settings.json` disagree about the advisor: tell the human in your first reply; work may continue.
