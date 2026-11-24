# agent-harness-template

A repository boilerplate for developing with coding agents (Claude Code). It is built on the idea of harness engineering: an agent's reliability is decided less by the prompt than by the environment around the model. Here that environment is a set of files you copy into any project.

## What is inside, in short

- **A task contract** before the first line of code (Gate 1: you approve it with `approve.sh`; until then a hook keeps the agent out of the code).
- **A ladder of checks** from cheap to expensive: lint, build, unit, arch, ui.
- **A critic agent** on a stronger model (opus), in a fresh context, read-only. Its job is to find a reason to reject the result.
- **A receipt** at the end: only what the system can prove (Gate 2: you read it and decide about the commit).
- **Hard stops** (deploy, App Store release, migrations) live in hooks and permissions, not in the prompt.
- **The project model** is pinned in `.claude/settings.json` and checked by a hook at session start, so a `/model` switch in another project does not leak here.
- **Advisor** (optional): a stronger model the main one consults at decision points. Pinned in `.claude/settings.json` the same way as the model.

## Quick start

```bash
cp -R agent-harness-template/. /path/to/project/    # or use it as a GitHub template
cd /path/to/project
chmod +x scripts/*.sh profiles/*/*.sh .claude/hooks/*.py
./scripts/init.sh                                   # name, profile (generic/ios), model, commands, vault
./scripts/check.sh                                  # see which steps are configured
python3 .claude/hooks/test_guard.py                 # test the Gate 1 hook on your machine
```

Obsidian is optional: press Enter at the vault question in `init.sh`, the path stays empty and the sync does nothing. Run `init.sh` in a project created from the template, not in the template repository itself: it writes local paths into `harness.yml`.

Then, in Claude Code, inside the project:

```
/task add X               -> creates tasks/<date-slug>/contract.md (status: DRAFT), contract-reviewer gives advice, the agent stops
                             you read the contract and answer the open questions
./scripts/approve.sh      -> in YOUR OWN terminal (not through the agent): the contract is approved and frozen, code is unlocked
                             the agent works and keeps state.md
/gate                     -> check.sh --full, then the critic; on REJECT the agent fixes and repeats (up to a limit)
/receipt                  -> tasks/<id>/receipt.md and a draft pr.md; code is locked again, the agent stops
                             you read the receipt and commit yourself
/retro                    -> if the failure was preventable: a diagnosis + one harness improvement
```

A base commit is needed so that `git diff HEAD` works in the first task: without it the critic has no diff and the evidence has to be collected by hand. If you declined it in `init.sh`, make it yourself before the first task.

Make the first task small and safe (for example, add a test to existing code). The goal of the first run is not the result but to see that the whole loop works.

## Gate 1: contract approval

The rule "code only after APPROVED" used to be an instruction. Now a hook enforces it.

- `./scripts/approve.sh` sets `status: APPROVED` in the contract and writes the sha256 of `contract.md` into `tasks/<id>/APPROVED`. The `guard.py` hook lets the agent touch project code only while the hash matches.
- The contract is frozen after approval. Any edit (yours, or the agent's around the hook) withdraws the approval: scope cannot be widened and acceptance cannot be weakened after the fact. If you edit the contract yourself, run `approve.sh` again.
- The agent cannot approve: the script requires a terminal and refuses to run inside Claude Code, the hook blocks running it and writing the approval files, and `settings.json` has a deny rule. A `status: APPROVED` line the agent wrote itself unlocks nothing.
- The receipt closes the task: once `receipt.md` exists, code is locked again. For follow-up work after the receipt, delete the receipt yourself or grant a quick approval.
- A quick lane for small things: `./scripts/approve.sh --quick [N]` opens up to N files (default 3, maximum 10) for 60 minutes with no contract and no critic. The hook counts the files itself.
- `./scripts/approve.sh --status` shows what is approved now. `--revoke` withdraws the approval.
- Without approval the agent can always edit `tasks/` and `docs/`. Extend the list with `ungated_paths` in `harness.yml`.
- The switch: `require_approval: false` in `harness.yml` puts the rule back at instruction level.

Run `approve.sh` in a separate terminal window. Through `!` inside Claude Code it refuses to work, by design.

## Work packages: a task in packages

Optional, enabled per task. Useful when a task crosses several layers and its parts can be done in sequence.

- The contract has a ` ```scope ` block: one line per package, `P1: glob, glob`. An empty block means an ordinary task and everything works as before.
- After approval the hook allows code edits only inside these globs. The block is part of the contract hash; widening it takes `approve.sh --revoke`, an edit and a new approval. On approval `approve.sh` prints the packages the hook will enforce.
- `/work` runs the packages one at a time: it writes the package id into `tasks/<id>/.package`, launches the `worker` subagent, reads its note `tasks/<id>/packages/<ID>.md` and runs the package check. A worker that needs a file outside its package, or finds two contract requirements incompatible, stops with status BLOCKED and the question goes to you.
- After the last package the orchestrator walks every acceptance item and looks for the named proof in the logs, not in the notes. Only then is the task ready for `/gate`. There is one critic, for the whole diff.
- Items about the task as a whole (old tests untouched, forbidden paths clean, the full run) belong to the orchestrator, not to the last package.

What two pilots in Tapestry showed (November 2026): the boundaries hold inside a subagent too, the notes hand the next worker everything it needs, and the evidence pass catches deviations before the critic. What packages did not give: fewer critic rounds, or speed (workers run one at a time). For a single-layer task of a few files, packages are overhead: two notes and a handoff between workers.

## Parallel tasks: several agents in their own directories

Optional. Useful when you have two or three independent tasks and want them to run at the same time. Parallelism lives at the task level, not the package level: every task has its own directory (a git worktree), its own branch, its own contract and its own critic.

1. In the main window: `/swarm <the tasks in your own words>`. The agent splits the work into tasks, checks for file overlaps and writes a plan to `tasks/.swarm-plan` (one line per task: `name | what to do`, and for a dependent one `name | after: other | what to do`). The plan is a task graph: `launch` starts only the tasks whose dependencies are already merged; run `launch` again after every `finish`. The agent touches no directories and no code.
2. You, in a terminal: `./scripts/swarm-worktree.sh launch`. For every task it creates a directory `../<repository>-<name>` on branch `task/<name>` and opens a Terminal window where `claude` starts with `/task`. In an iOS project every directory gets its own simulator.
3. `./scripts/swarm-worktree.sh status` shows what each task is waiting for. `./scripts/swarm-worktree.sh approve` runs Gate 1 from the same terminal: it shows the contract's objective and the reviewer's verdict and asks about each task.
4. Gate 2 as usual: you read the receipt and commit in the task's directory.
5. `./scripts/swarm-worktree.sh finish` merges the committed branches, runs `check.sh --full` once on the combined result and removes the merged directories. On a merge conflict it stops and deletes nothing.

Only a human runs the script: it works outside the repository folder. Windows open through Terminal on macOS; on another system the script prints the command to run in a new window.

What two trials in Tapestry showed (November 2026): the harness works in a separate directory without changes; between Gate 1 and Gate 2 the tasks do not need the human, whose time goes to contracts at the start and to receipts and merging at the end; a conflict in a shared file (the dependency build root, a table in `docs/architecture.md`) is resolved by hand in minutes. More than three tasks at once has not been tried.

## The project model

The problem: `/model` confirmed with Enter writes the model into user settings (a machine-wide default), while `CLAUDE.md` and the contract cannot select a model (to Claude Code they are just text). So a switch in one project changed the model in all of them.

How it works here:

- `model:` in `harness.yml` is the source of truth. `init.sh` asks for the model (default `sonnet` for routine work, `opus` for heavy architecture) and writes it into `harness.yml` and into `"model"` in `.claude/settings.json`. Project settings take priority over user settings, so the project starts on its own model.
- The contract has an optional `model:` (default `default`) for a task that needs a different model. Switching the model in a session is the human's job through `/model`: the agent cannot.
- The `.claude/hooks/model-check.py` hook compares the session model with the expected one at session start (an `APPROVED` contract without a receipt > `harness.yml`). On a mismatch it shows `MODEL MISMATCH` to you and to the agent; the agent must say so in its first reply and not start work.
- The hook only warns. It cannot make Claude Code switch models, and `/model` inside a session takes priority over the pin.
- If you choose a model through `/model` in a project with a different pin, Claude Code may save the choice into that project's `.claude/settings.local.json` (version-dependent). The same hook checks it then.
- Choosing a model "for this session only" in the `/model` picker depends on the Claude Code version: check which key does it on yours.

### Advisor (optional)

`/advisor` saves the choice into user settings (it leaks the same way `/model` does), so it is pinned on the same principle.

- `advisor:` in `harness.yml` (`none`, `opus`, `fable` or a full id) is the source of truth. `init.sh` asks for it after the model, checks that the advisor is not weaker than the project model (for known names) and writes `"advisorModel"` into `.claude/settings.json`. With `none` the key is not written.
- The `model-check.py` hook compares configuration only (`harness.yml` and `settings.json`) and shows `ADVISOR DRIFT` when they disagree. Claude Code does not expose the live advisor state to hooks, so the receipt has an ADVISOR line: the number of consultations recorded in `state.md`, or UNVERIFIED.
- `advisor: none` only means "the project pins nothing": an advisor enabled globally through `/advisor` can still apply.
- Enter in the `/advisor` picker writes the choice into user settings, Esc cancels.
- The advisor works inside the session's own context and does not replace the independent `critic`. `CLAUDE.md` has a "when to call it" line for it: without one there is no guarantee the model will call it.
- Fable as an advisor needs Claude Code v2.1.170+ and access to Fable.

For existing projects without the template, adding `"model": "sonnet"` (or `"opus"`) to their `.claude/settings.json` is enough.

## File map

| File | Purpose |
|---|---|
| `CLAUDE.md` | a short project map and the hard rules. The agent always reads it |
| `harness.yml` | settings: model, advisor, Gate 1, check commands, budgets, your own stops, protected and ungated paths, vault. The agent cannot edit it |
| `.claude/settings.json` | project model, advisor, permissions (allow / ask / deny) and hook wiring |
| `.claude/hooks/guard.py` | blocks dangerous commands, edits to protected files, code edits without an approved contract (Gate 1) and edits outside the approved contract's `scope` block |
| `.claude/hooks/test_guard.py` | synthetic tests for `guard.py` and `approve.sh`; one command runs them |
| `.claude/hooks/model-check.py` | warns at session start when the model differs from the expected one (project or contract) or the advisor disagrees with `harness.yml` |
| `.claude/agents/critic.md` | the critic: read-only, model opus, verdict format ACCEPT / REJECT |
| `.claude/agents/contract-reviewer.md` | reviewer of the draft contract: read-only, model opus, advice before Gate 1 (READY / REVISE); the human still decides |
| `.claude/agents/worker.md` | the worker: does exactly one work package of the contract in a fresh context, writes only inside its package's globs, leaves a note in `tasks/<id>/packages/` |
| `.claude/commands/` | `/task`, `/work`, `/gate`, `/receipt`, `/retro`, `/swarm` |
| `docs/` | `architecture.md`, `commands.md`, `release.md`: filled in per project |
| `tasks/_TEMPLATE/` | templates for `contract.md`, `state.md`, `receipt.md` |
| `.github/pull_request_template.md` | PR template; `/receipt` builds a draft `tasks/<id>/pr.md` from it with "must not change" and acceptance checkboxes |
| `tasks/lessons.md` | the lessons log (flywheel); the agent reads it before a task |
| `scripts/approve.sh` | Gate 1: contract approval and quick approval. Only a human runs it |
| `scripts/check.sh` | the ladder of checks; writes `checks.log` into the active task |
| `scripts/evidence.sh` | matches the test names in the contract's acceptance items against `checks.log`: where each one passed and whether on the current build (`work=`). Read-only; the evidence pass step of `/gate` calls it |
| `scripts/init.sh` | one-time project setup |
| `scripts/swarm-worktree.sh` | parallel tasks: `launch`, `status`, `approve`, `finish`. Only a human runs it |
| `scripts/sync-obsidian.sh` | copies the receipt into an Obsidian vault (one way) |
| `profiles/` | command sets per stack; `ios` includes a pattern-based architecture check |

## Where state lives

The source of truth is the repository (`tasks/`): it is versioned and the agent reads it itself. Obsidian is a read-only copy: `sync-obsidian.sh` puts the receipt into `<vault>/agent-runs/<project>/`. There is no two-way sync, on purpose.

## What is actually enforced and what is only an instruction

| Rule | How it is held |
|---|---|
| Deploy, fastlane, `xcrun altool`, `-exportArchive`, publish, migrations, terraform/kubectl apply, force push | **hook + deny** (the agent physically cannot run it) |
| Edits to `harness.yml`, `.claude/settings*`, the hooks, the critic, `.env*`, paths in `protected_paths` | **hook** |
| Writing outside the project folder | **hook** |
| The critic changes nothing | **tools: Read, Grep, Glob** (no Edit, no Bash) |
| `git add / commit / push / merge / reset` | **ask**: asks you every time |
| The project model | **`"model"` in settings.json sets the model at start; a hook warns on a mismatch**. Switching in a session through `/model` is not blocked |
| No code before the contract is approved | **hook** on Edit/Write: needs `tasks/<id>/APPROVED` with the contract hash, or a quick approval. The hook does not see writes through Bash; those are held by the `allow` list (everything else asks you) |
| Only a human approves | **hook + deny + a terminal check** in `approve.sh` |
| The contract does not change after approval | **hook** (the file is frozen) **+ hash** (an edit around the hook withdraws the approval) |
| Code edits only inside the contract's scope | **hook**, if the contract's `scope` block is filled in: the glob list is part of the approved contract's hash and the agent cannot widen it. An empty block = no check |
| A worker edits only its own package | **hook driven by `tasks/<id>/.package`**, which the `/work` orchestrator writes: protection against accident, not against intent |
| A worker's DONE and "ready for `/gate`" | **instruction**: the worker reports DONE only with named proofs; before `/gate` the orchestrator looks for the proof of every acceptance item in the logs |
| The contract's "must not change" is untouched | **critic + SCOPE CHECK in the receipt and the PR** (checked against the diff and visible to the reviewer; no automatic script yet, behaviour without paths is left to the critic) |
| Tests must not be weakened | **instruction + critic** (it checks this in the diff) |
| Retry and diff-size limits | **instruction** (`budgets` in `harness.yml`); the agent watches them itself |

Weak points worth knowing. First: Gate 1 covers the Edit and Write tools, not Bash. A command like `sed -i` on a project file is not checked by the hook: it is stopped only because it is not in `allow`, so Claude Code asks you. If you work in a mode without confirmations, this protection is gone. Second: the `guard.py` hook matches commands by pattern, not by meaning. It will not notice an obfuscated call (for example, a script that itself calls fastlane or writes the approval file). Third: the agent can edit `scripts/check.sh` and `profiles/`, so in theory it can weaken the checks themselves; that shows in the diff and is left to the critic. For "the agent must not do this by accident" this is enough. It is not protection against malicious intent.

## Customising for a project

1. `./scripts/init.sh`: name, profile, model, check commands.
2. `docs/architecture.md`: layers, dependency direction, where new code goes. Keep it short and checkable.
3. `profiles/ios/layers.rules`: add architecture rules one at a time, after real failures. It works on patterns in file text. For layers that are modules (SPM targets) matching `import` is convenient; for layers that are folders you will have to match type names or write XCTest checks and put them into the `unit` step.
4. `harness.yml`: `protected_paths` (for example `**/Generated/**`), your own `blocked_commands`, `ungated_paths`.
5. A new stack: create `profiles/<name>/commands.yml` (see `profiles/README.md`).

## Principles behind it

- A contract instead of a vague request, proof instead of the word "done".
- Cheap deterministic checks first; a model only where there is ambiguity.
- Verification is an attempt to disprove, not a second opinion: the critic has a fresh context and can only reject.
- A rule that matters repeatedly moves up the ladder: explanation, checklist, template, automated check, enforced policy.
- Complexity follows failures. There is deliberately no automatic failure classification or self-learning here: first `/retro` by hand, and only repeated failures become automation.
- A harness ages. Every couple of months, check which gates and rules are no longer needed (models improve) and remove them.

## Known limitations

- UI tests on a simulator are slow and flaky. They are the last step and run only in `--full` and `/gate`.
- A step with status SKIP does not count as passed: it goes into NOT VERIFIED. Until `arch` is configured, the critic checks architecture from the diff only.
- On a second run `init.sh` does not rename the `CLAUDE.md` heading (the placeholder is already replaced). Fix it by hand.
- The scripts are tested on Linux. On macOS they target the stock bash 3.2 and the `python3` from Xcode Command Line Tools, but make the first run on your Mac yourself.
- The template has been run on one project (Tapestry, iOS, about 40 tasks). On another stack treat the first run as a test: take a small first task.
- `model-check.py` is tested only on synthetic inputs (match, mismatch, contract override, missing field). Whether your Claude Code version passes the `model` field in SessionStart has not been checked in a live session; if it does not, the hook says "cannot verify" instead of staying silent.
- The hook (Gate 1 and scope) and `approve.sh` are tested with synthetic tests (`python3 .claude/hooks/test_guard.py`, 85 cases) on Linux and on macOS. Confirmed in live Claude Code sessions in Tapestry: the hook fires on edits from a subagent. Not checked: whether your Claude Code version sets the `CLAUDECODE` variable (the terminal check does not depend on it).
- A project created from an older version of the template: after `guard.py` is updated, Gate 1 turns on immediately, even if its `harness.yml` has no `require_approval` key. Copy `scripts/approve.sh` together with the hook.

## Licence

MIT, see `LICENSE`.
