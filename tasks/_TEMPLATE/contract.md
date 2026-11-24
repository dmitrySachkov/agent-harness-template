---
status: DRAFT        # set to APPROVED by ./scripts/approve.sh, which only the HUMAN runs (Gate 1). No project code before that; the contract is frozen after it.
model: default       # default = the model from harness.yml; or sonnet / opus for this task. The HUMAN switches with /model; the SessionStart hook warns on a mismatch.
id: __ID__
created: __DATE__
---

# Contract: __TITLE__

## Objective
<!-- The outcome that must exist, 1-2 sentences. Not the steps. -->

## Scope (in)
<!-- Concrete files, modules, behaviors this task may touch. -->
-

## Work packages
<!-- Optional. Leave the block below empty for a task done in one piece.
With at least one line in it, the hook enforces it after approval: project files outside these globs cannot be edited
at all, and while `/work` runs a package only that package's globs are open.
One package per line: `ID: glob, glob`. Globs are relative to the repo root; `*` also matches `/`.
Cover every file under Scope (in) exactly once, new files included. Packages must not overlap. Line order = work order. -->
```scope
```
<!-- For each package: what it delivers; which acceptance items it owns; which check must be green when it ends
(say so if the build cannot be green before a later package); what it needs from earlier packages.
Items about the whole change (existing tests unchanged, forbidden paths untouched, the full run) belong to the
orchestrator after the last package: say so here. -->
-

## Out of scope / must not change
<!-- Anything untouchable: other modules, public API, auth, existing behavior. Write each item as a concrete path or glob in backticks plus a few words on behavior, so the receipt's SCOPE CHECK can be proven from the diff. -->
-

## Acceptance evidence
<!-- Each item says HOW it will be proven. Deterministic proof first. -->
- [ ] <item> -- proof: <named test / check step / recorded observation>

## Requires human approval
<!-- Deploy, store release, migration, secrets, external side effects. "none" if none. -->
-

### Outside the repo
<!-- "none" if the task stays in the repo. Hooks do not check Bash here, so this text is the only limit.
Grant by place, not by a command list: a list misses every helper step and turns it into a violation.
For each place: path; what may be written; what may be deleted. Deletions are named exactly.
The scratchpad gets a line of its own: helper files are normal there.
Anything else outside these places: ask the human first. -->
- none

## Open questions
<!-- Everything ambiguous. The agent asks; it does not guess. -->
-
