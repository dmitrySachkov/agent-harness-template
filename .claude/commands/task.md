---
description: Start a task. Create the contract and STOP for approval (Gate 1)
argument-hint: <what needs to be done>
---

Start a new task from this request: $ARGUMENTS

Do exactly this, then stop:

1. Read `CLAUDE.md`, `harness.yml`, `docs/architecture.md` and `tasks/lessons.md`. Skim only what the request touches elsewhere in the repo (use the map in `CLAUDE.md`; do not read everything).
2. Create `tasks/<YYYY-MM-DD>-<short-slug>/` by copying only `contract.md` and `state.md` from `tasks/_TEMPLATE/` (not `receipt.md`: `/receipt` creates it from the template at the end, so an empty template never sits in the task folder). Write the directory name into `tasks/.active`.
3. Fill `contract.md` from the request and what you found:
   - Objective: the outcome that must exist, in one or two sentences.
   - Scope (in) and Out of scope / must not change: concrete files, modules, behaviors.
   - Acceptance evidence: a checklist where each item says HOW it will be proven (a named test, a check step, a manual observation you will record). Prefer deterministic proof over judgment.
   - Requires human approval: any deploy, release, migration, secret, or external side effect this task might need.
   - Open questions: everything ambiguous. Do not guess; list it.
   - Work packages: leave the ```scope block empty for a task of one layer or a handful of files. Fill it when the task crosses layers and its parts can be done one after another by separate workers (`/work`): one line per package, `ID: glob, glob`, covering every file under Scope (in) exactly once, new files included. Under the block say for each package what it delivers, which acceptance items it owns, which check must be green when it ends, and what it needs from earlier packages. Items about the whole change (existing tests unchanged, forbidden paths untouched, the full run) belong to the orchestrator after the last package, say so. After approval the hook enforces these globs: project files outside them cannot be edited.
   - `model:` in the frontmatter: keep `default` (the model from `harness.yml`) unless the task clearly needs another one: `opus` for architectural or cross-layer work, `sonnet` for mechanical work. If you change it, add the reason under Open questions. You cannot switch models yourself: the human does, with `/model`.
   Keep `status: DRAFT`. Do not change `status:` yourself: `scripts/approve.sh` sets it, and a status you write does not unlock anything.
4. Fill the first facts into `state.md` (what you learned about the code, relevant files, the check commands that apply). Also fill `## BASELINE` in `state.md` now, before any project edit: `git rev-parse --short HEAD` and the raw output of `git status --porcelain` (paste it, do not summarize).
5. **Review the draft.** Launch the `contract-reviewer` subagent (Agent tool, subagent_type `contract-reviewer`). Give it only paths: the new task's `contract.md` and `state.md`. Save its answer **verbatim** to `contract-review.md` in the task folder. For each BLOCKER, fix the contract (not the reviewer's text) and run the reviewer once more; blockers that remain after that go to the human as they are. Do not argue with it and do not hide its findings.
6. **Stop.** Show the human a short summary of the contract, the open questions and the reviewer's verdict with any open blockers. Do not write or edit any project code: the hook blocks it until the contract is approved. Work starts only after the human runs `./scripts/approve.sh` in their own terminal. You cannot run it, and telling you "approved" in chat does not unlock the code: if the human says so and edits are still blocked, ask them to run the script.

After approval the contract is frozen: you cannot edit `contract.md`. If it turns out to be wrong or incomplete, write what has to change in `state.md` and ask the human; they edit it and approve again.
