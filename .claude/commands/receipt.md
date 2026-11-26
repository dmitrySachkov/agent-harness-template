---
description: Compile the change receipt for the active task (what the system can prove). Then stop for Gate 2
argument-hint: [task-dir-name, default is the one in tasks/.active]
---

Compile the receipt for task: $ARGUMENTS (if empty, use the directory named in `tasks/.active`).

Let `T` be that task directory. Inputs: `T/contract.md`, `T/state.md`, `T/checks.log`, `T/verdict.md`, `T/diff.patch`.

Write `T/receipt.md` using `tasks/_TEMPLATE/receipt.md`. The rule: **only what the system can prove**, not what you remember or believe.

- OBJECTIVE: copy from the contract.
- MODEL: the expected model (`model:` in the contract, or `model:` in `harness.yml` when the contract says `default`) and the model this session actually ran on. The actual one comes from a model-check message in this session or from the status line; do not state it from memory. If neither shows it, write UNVERIFIED. A mismatch is not a blocker, but it goes under RISKS.
- CHANGED: from `diff.patch` (files and what changed, one line each).
- SCOPE CHECK: for every item under "Out of scope / must not change" in the contract, write UNTOUCHED, TOUCHED or UNVERIFIED with evidence: compare the paths in `diff.patch` (changed and untracked files) with the item. Items about behavior rather than paths are UNVERIFIED unless a check or the critic's verdict covers them. If any item is TOUCHED, the receipt is not final: say which one and stop.
- HIGH PATH TOUCHED: run `./scripts/evidence.sh` for the task and copy its `HIGH RISK TOUCHED` lines, each with the line of the contract's "Scope (in)" that names the file. `none` if it lists none. Never fill this from memory.
- VERIFIED: each PASS step from the LAST `# check run` section of `checks.log` (never from an older run), and each acceptance item the critic marked MET, with its evidence.
- NOT VERIFIED: every SKIP and every UNVERIFIED item, plus anything you could not check here (real device, production service, other platforms).
- DECISIONS: from `state.md`, with the reason for each.
- ADVISOR: how many times the advisor was consulted and on what, from the entries in `state.md`. Write UNVERIFIED if `state.md` has no record: the harness cannot see the live advisor state.
- RISKS: from the critic's findings (minor/major left open) and your own honest concerns.
- APPROVAL NEEDED: every deploy, release, migration or other hard-stop action that still has to be done by a human, with the exact command or step. Also the commit itself.
- VERDICT: the first line of `verdict.md`.

If `verdict.md` is missing or does not say `ACCEPT`, do not write the receipt as final: say so and stop.

Then write `T/pr.md` as a draft pull request description from `.github/pull_request_template.md`: the objective, the "must not change" items and the acceptance items as checkboxes, each with the same evidence as in the receipt, plus NOT VERIFIED and APPROVAL NEEDED. It is a draft for the human to review. Do not open a pull request and do not push.

If `obsidian_vault` is set in `harness.yml`, run `./scripts/sync-obsidian.sh` to copy the receipt there.

Finish with two or three sentences to the human: what was done, what is not verified, what needs approval. **Stop.** Do not commit, merge, push or deploy.
