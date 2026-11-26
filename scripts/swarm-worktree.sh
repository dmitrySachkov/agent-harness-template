#!/usr/bin/env bash
# Parallel tasks: extra checkouts of this repo, one per task, each with its own agent.
# Run it yourself, from the main checkout. Each checkout gets its own branch, its own tasks/.active
# and its own simulator, so two agents do not install over each other's build.
#
# Usage:
#   scripts/swarm-worktree.sh launch          read tasks/.swarm-plan; for each task that is ready (everything it comes
#                                             after is merged) create a checkout and open a Terminal window there
#                                             with `claude "/task <description>"`. Run it again after `finish`.
#   scripts/swarm-worktree.sh status          what each checkout is waiting for (your approval, the agent, your commit)
#   scripts/swarm-worktree.sh approve [name]  Gate 1 from this terminal: for each checkout whose contract is not approved,
#                                             show it and ask y/N (no need for a second terminal per checkout)
#   scripts/swarm-worktree.sh finish          merge every committed task branch, run check.sh --full once,
#                                             then remove the merged checkouts. Stops at a merge conflict.
#   scripts/swarm-worktree.sh add <name>      create ../<repo>-<name> on branch task/<name> (no window)
#   scripts/swarm-worktree.sh list            show the checkouts
#   scripts/swarm-worktree.sh remove <name>   after the branch is merged: remove the checkout, its simulator and the branch
#
# tasks/.swarm-plan is the task graph: one task per line, lines starting with # are skipped.
#   name | what needs to be done                      a task that can start at once
#   name | after: a, b | what needs to be done        a task that starts only when a and b are merged
#   + name | ...                                      merged; `finish` puts the + there, do not write it yourself
# The /swarm command writes the plan; you can also write it by hand.
#
# What `add` does:
#   1. iOS projects only (harness.yml has a 'platform=iOS Simulator,name=...,OS=...' destination): creates a simulator
#      "<device> swarm-<name>" with the same device type and iOS version;
#   2. git worktree add -b task/<name> ../<repo>-<name>;
#   3. in that checkout only, points harness.yml and docs/commands.md at the new simulator and tells git
#      to ignore that local edit (skip-worktree), so it never reaches a commit or a diff.
# The harness needs nothing else: the hook takes the project root from the folder Claude Code runs in,
# and tasks/.active is not in git.
#
# Test switches: SWARM_NO_SIM=1 skips simulators, SWARM_NO_OPEN=1 prints the window command instead of opening it,
# SWARM_NO_CHECK=1 skips check.sh in `finish`.
set -eu

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REPO="$(basename "$ROOT")"
CMD="${1:-}"
PLAN="tasks/.swarm-plan"

case "$CMD" in
  list) git worktree list; exit 0 ;;
  add|remove|launch|finish|status|approve) ;;
  *) sed -n '2,24p' "$0"; exit 64 ;;
esac

[ "$(git rev-parse --git-dir)" = ".git" ] || { echo "Run this from the main checkout, not from a worktree." >&2; exit 1; }

# device and iOS version: the first simulator destination in harness.yml
DEVICE="$(sed -n "s/.*platform=iOS Simulator,name=\([^,']*\),OS=\([0-9.]*\).*/\1/p" harness.yml | head -n 1)"
OSV="$(sed -n "s/.*platform=iOS Simulator,name=\([^,']*\),OS=\([0-9.]*\).*/\2/p" harness.yml | head -n 1)"
# no iOS simulator destination in harness.yml: not an iOS project, checkouts need no simulator of their own
if [ -z "$DEVICE" ] || [ -z "$OSV" ]; then SWARM_NO_SIM=1; fi

valid_name() { printf '%s' "$1" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; }
dest_of()    { printf '%s/%s-%s' "$(dirname "$ROOT")" "$REPO" "$1"; }
have_sim()   { xcrun simctl list devices | grep -Fq "    $1 ("; }
is_merged()  { git branch --merged | grep -Eq "^[*+ ] +$1\$"; }

do_add() {
  name="$1"; dest="$(dest_of "$name")"; branch="task/$name"; sim="$DEVICE swarm-$name"
  [ ! -e "$dest" ] || { echo "Already exists: $dest" >&2; return 1; }
  if git show-ref --verify --quiet "refs/heads/$branch"; then echo "Branch $branch already exists." >&2; return 1; fi

  if [ -z "${SWARM_NO_SIM:-}" ]; then
    command -v xcrun >/dev/null 2>&1 || { echo "xcrun not found. This needs Xcode." >&2; return 1; }
    if have_sim "$sim"; then
      echo "simulator already exists: $sim"
    else
      runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
for r in json.load(sys.stdin).get("runtimes", []):
    if r.get("isAvailable") and r.get("platform", "iOS") == "iOS" and r.get("version") == want:
        print(r["identifier"]); break
' "$OSV")"
      [ -n "$runtime" ] || { echo "No installed iOS $OSV simulator runtime (xcrun simctl list runtimes)." >&2; return 1; }
      xcrun simctl create "$sim" "$DEVICE" "$runtime" >/dev/null
      echo "simulator created: $sim (iOS $OSV)"
    fi
  fi

  git worktree add -q -b "$branch" "$dest"
  git rev-parse HEAD > "$(cd "$dest" && cd "$(git rev-parse --git-dir)" && pwd)/swarm-base"   # where the task started

  # point this checkout at its own simulator; the edit stays local
  if [ -n "$DEVICE" ]; then
    for f in harness.yml docs/commands.md; do
      [ -f "$dest/$f" ] || continue
      if grep -Fq "name=$DEVICE,OS=" "$dest/$f"; then
        python3 - "$dest/$f" "name=$DEVICE,OS=" "name=$sim,OS=" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text.replace(old, new))
PY
        git -C "$dest" update-index --skip-worktree "$f"
      fi
    done
  fi
  if [ -f .claude/settings.local.json ]; then cp .claude/settings.local.json "$dest/.claude/settings.local.json"; fi
  echo "ready: $dest   branch $branch"
}

do_remove() {
  name="$1"; dest="$(dest_of "$name")"; branch="task/$name"; sim="$DEVICE swarm-$name"
  [ -d "$dest" ] || { echo "No checkout at $dest" >&2; return 1; }
  if ! is_merged "$branch"; then
    echo "Branch $branch is not merged into $(git branch --show-current). Merge it first, or remove the checkout by hand." >&2
    return 1
  fi
  # Numbered diffs of the critic rounds are git-ignored, so they would die with the checkout: keep them by the verdicts.
  for p in "$dest"/tasks/*/diff.attempt-*.patch; do
    [ -f "$p" ] || continue
    keep="tasks/$(basename "$(dirname "$p")")"
    if [ -d "$keep" ]; then cp -n "$p" "$keep/" 2>/dev/null || true; fi
  done
  git worktree remove --force "$dest"
  git branch -d "$branch"
  if [ -z "${SWARM_NO_SIM:-}" ] && have_sim "$sim"; then xcrun simctl delete "$sim"; echo "simulator removed: $sim"; fi
  echo "removed: $dest and branch $branch"
}

# Opens a Terminal window in the checkout and starts claude with the task as its first message.
# The message is kept in the checkout's private git folder, so it can never be committed and no quoting is lost.
open_window() {
  dest="$1"; text="$2"
  pfile="$(cd "$dest" && cd "$(git rev-parse --git-dir)" && pwd)/swarm-prompt"
  printf '/task %s\n' "$text" > "$pfile"
  q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
  line="cd $(q "$dest") && claude \"\$(cat $(q "$pfile"))\""
  if [ -n "${SWARM_NO_OPEN:-}" ]; then echo "would open: $line"; return 0; fi
  command -v osascript >/dev/null 2>&1 || { echo "osascript not found; run yourself: $line"; return 0; }
  esc="$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  osascript -e "tell application \"Terminal\" to do script \"$esc\"" -e 'tell application "Terminal" to activate' >/dev/null
  echo "window opened: $dest"
}

# Reads the plan and prints one validated row per task, tab-separated: state (done|todo), name, deps (a,b or -), text.
# Stops with a message on a bad line, an unknown or self dependency, a duplicate name or a cycle.
plan_rows() {
  python3 - "$PLAN" <<'PY'
import re, sys
path = sys.argv[1]
rows, seen = [], {}
for n, raw in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    state = "todo"
    if line.startswith("+"):
        state, line = "done", line[1:].strip()
    parts = [p.strip() for p in line.split("|")]
    if len(parts) < 2:
        sys.exit("%s:%d: no '|' in line: %s" % (path, n, raw))
    name, deps = parts[0], []
    if re.match(r"^after\s*:", parts[1]):
        deps = [d for d in re.split(r"[,\s]+", parts[1].split(":", 1)[1].strip()) if d]
        text = " | ".join(parts[2:]).strip()
    else:
        text = " | ".join(parts[1:]).strip()
    if not re.match(r"^[a-z0-9][a-z0-9-]*$", name):
        sys.exit("%s:%d: bad name '%s' (lowercase letters, digits, dashes)" % (path, n, name))
    if not text:
        sys.exit("%s:%d: task '%s' has no description" % (path, n, name))
    if name in seen:
        sys.exit("%s:%d: name '%s' is used twice" % (path, n, name))
    seen[name] = deps
    rows.append((state, name, deps, text))
for state, name, deps, text in rows:
    for d in deps:
        if d == name or d not in seen:
            sys.exit("%s: task '%s' comes after '%s', which is not a task of this plan" % (path, name, d))
left = dict(seen)
while left:
    free = [k for k, v in left.items() if not any(d in left for d in v)]
    if not free:
        sys.exit("%s: the tasks wait for each other in a circle: %s" % (path, ", ".join(sorted(left))))
    for k in free:
        del left[k]
for state, name, deps, text in rows:
    print("\t".join([state, name, ",".join(deps) or "-", text.replace("\t", " ")]))
PY
}

# Puts the + mark on the plan lines of merged tasks; when every task is merged, the plan is archived.
plan_mark_done() {
  [ -f "$PLAN" ] || return 0
  python3 - "$PLAN" "$@" <<'PY'
import sys
path, names = sys.argv[1], set(sys.argv[2:])
out = []
for raw in open(path, encoding="utf-8").read().split("\n"):
    line = raw.strip()
    if line and not line.startswith(("#", "+")) and line.split("|")[0].strip() in names:
        raw = "+ " + line
    out.append(raw)
with open(path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out))
PY
}

# One line of state for a checkout: the active task and what it waits for. Sets $task and $gate (none|draft|void|approved|done).
checkout_state() {
  dest="$1"; task=""; gate="none"
  [ -f "$dest/tasks/.active" ] && task="$(tr -d '[:space:]' < "$dest/tasks/.active")"
  [ -n "$task" ] && [ -f "$dest/tasks/$task/contract.md" ] || { task=""; return 0; }
  line="$(cd "$dest" && ./scripts/approve.sh --status 2>/dev/null | head -n 1)"
  case "$line" in
    *"finished (receipt exists)"*) gate="done" ;;
    *"APPROVAL VOID"*)             gate="void" ;;
    *"NOT APPROVED"*)              gate="draft" ;;
    *"-> APPROVED"*)               gate="approved" ;;
  esac
}

task_names() {
  for branch in $(git for-each-ref --format='%(refname:short)' 'refs/heads/task/*'); do
    [ -d "$(dest_of "${branch#task/}")" ] && printf '%s\n' "${branch#task/}"
  done
  return 0
}

case "$CMD" in
  status)
    found=""
    for name in $(task_names); do
      found=1; dest="$(dest_of "$name")"; checkout_state "$dest"
      ahead="$(git rev-list --count "HEAD..task/$name")"
      dirty=""; [ -z "$(git -C "$dest" status --porcelain)" ] || dirty=", uncommitted changes"
      case "$gate" in
        none)     what="no contract yet (the agent is still writing it, or /task was not run)" ;;
        draft)    what="WAITS FOR YOU: contract not approved  ->  scripts/swarm-worktree.sh approve" ;;
        void)     what="WAITS FOR YOU: contract changed after approval  ->  scripts/swarm-worktree.sh approve" ;;
        approved) what="the agent is working" ;;
        done)     if [ -n "$dirty" ]; then what="WAITS FOR YOU: receipt is written, read it and commit in $dest"
                  else what="committed, ready for: scripts/swarm-worktree.sh finish"; fi ;;
      esac
      printf '%-22s %s\n' "$name" "${task:--}"
      printf '%-22s %s  (commits: %s%s)\n' "" "$what" "$ahead" "$dirty"
    done
    [ -n "$found" ] || echo "No task checkouts."
    if [ -s "$PLAN" ]; then
      rows="$(plan_rows)" || exit 64
      donelist=" $(printf '%s\n' "$rows" | awk -F'\t' '$1=="done"{printf "%s ", $2}')"
      echo
      echo "Plan ($PLAN):"
      printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r state name deps text; do
        if [ "$state" = "done" ]; then what="merged"
        elif [ -d "$(dest_of "$name")" ]; then what="started (see above)"
        else
          wait=""
          if [ "$deps" != "-" ]; then
            for d in $(printf '%s' "$deps" | tr ',' ' '); do case "$donelist" in *" $d "*) ;; *) wait="$wait $d" ;; esac; done
          fi
          if [ -n "$wait" ]; then what="waits for:$wait"; else what="READY  ->  scripts/swarm-worktree.sh launch"; fi
        fi
        printf '  %-22s %s\n' "$name" "$what"
      done
    fi
    ;;

  approve)
    if [ -n "${CLAUDECODE:-}" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "approve: approval is a human action. Run it yourself in your own terminal." >&2; exit 1
    fi
    ONLY="${2:-}"
    if [ -n "$ONLY" ]; then
      valid_name "$ONLY" && [ -d "$(dest_of "$ONLY")" ] || { echo "No checkout for '$ONLY'." >&2; exit 1; }
      list="$ONLY"
    else
      list="$(task_names)"
    fi
    asked=""
    for name in $list; do
      dest="$(dest_of "$name")"; checkout_state "$dest"
      case "$gate" in draft|void) ;; *) continue ;; esac
      asked=1; T="$dest/tasks/$task"
      echo
      echo "== $name: $task"
      [ "$gate" = "void" ] && echo "   (was approved, the contract changed since)"
      awk '/^## *Objective/{f=1; next} /^## /{f=0} f && NF' "$T/contract.md" | head -n 6 | sed 's/^/   /'
      if [ -f "$T/contract-review.md" ]; then
        echo "   reviewer: $(grep -m1 '^VERDICT:' "$T/contract-review.md" || echo 'no VERDICT line')"
      else
        echo "   reviewer: no contract-review.md yet (the agent may still be working on the draft)"
      fi
      echo "   contract: $T/contract.md"
      printf '   Approve? [y = yes / o = open the contract first / anything else = skip] '
      read -r ans
      if [ "$ans" = "o" ]; then
        if command -v open >/dev/null 2>&1; then open "$T/contract.md"; else echo "   open it yourself: $T/contract.md"; fi
        printf '   Approve now? [y/N] '
        read -r ans
      fi
      if [ "$ans" = "y" ]; then
        (cd "$dest" && ./scripts/approve.sh "$task")
        echo "   Tell the agent in that window: approved, go on."
      else
        echo "   skipped"
      fi
    done
    [ -n "$asked" ] || echo "Nothing waits for approval. See: scripts/swarm-worktree.sh status"
    ;;

  add)
    NAME="${2:-}"
    valid_name "$NAME" || { echo "Name: lowercase letters, digits and dashes, got: '$NAME'" >&2; exit 64; }
    [ -z "$(git status --porcelain)" ] || echo "NOTE: the main checkout has uncommitted changes. The new checkout starts from the last commit, without them."
    do_add "$NAME"
    echo
    echo "Next:  cd \"$(dest_of "$NAME")\" && claude      then /task as usual. Approve in that folder: ./scripts/approve.sh"
    echo "When its Gate 2 commit is done, here:  scripts/swarm-worktree.sh finish"
    ;;

  remove)
    NAME="${2:-}"
    valid_name "$NAME" || { echo "Name: lowercase letters, digits and dashes, got: '$NAME'" >&2; exit 64; }
    do_remove "$NAME"
    ;;

  launch)
    [ -s "$PLAN" ] || { echo "No $PLAN. Ask the agent in this checkout: /swarm <the tasks>, or write it by hand: name | what to do" >&2; exit 1; }
    [ -z "$(git status --porcelain)" ] || echo "NOTE: the main checkout has uncommitted changes. The new checkouts start from the last commit, without them."
    rows="$(plan_rows)" || exit 64
    [ -n "$rows" ] || { echo "$PLAN has no tasks." >&2; exit 1; }
    donelist=" $(printf '%s\n' "$rows" | awk -F'\t' '$1=="done"{printf "%s ", $2}')"
    names=""; held=""; running=""
    tab="$(printf '\t')"
    while IFS="$tab" read -r state name deps text; do
      [ "$state" = "done" ] && continue
      if [ -e "$(dest_of "$name")" ] || git show-ref --verify --quiet "refs/heads/task/$name"; then running="$running $name"; continue; fi
      wait=""
      if [ "$deps" != "-" ]; then
        for d in $(printf '%s' "$deps" | tr ',' ' '); do case "$donelist" in *" $d "*) ;; *) wait="$wait $d" ;; esac; done
      fi
      if [ -n "$wait" ]; then held="$held $name(after:$(printf '%s' "$wait" | tr ' ' ','))"; continue; fi
      do_add "$name"
      open_window "$(dest_of "$name")" "$text"
      names="$names $name"
    done <<EOF_ROWS
$rows
EOF_ROWS
    echo
    [ -z "$running" ] || echo "Already started:$running"
    [ -z "$held" ] || echo "Waiting: $(printf '%s' "$held" | sed 's/(after:,/(after: /g; s/^ //')"
    if [ -z "$names" ]; then
      echo "Nothing new to start. See: scripts/swarm-worktree.sh status"
      exit 0
    fi
    echo "Launched:$names"
    echo "When the drafts are ready, approve them from this terminal:  scripts/swarm-worktree.sh approve"
    echo "What waits for you at any moment:  scripts/swarm-worktree.sh status"
    echo "When the tasks are committed (Gate 2), here:  scripts/swarm-worktree.sh finish"
    [ -z "$held" ] || echo "After finish, run launch again: it starts the tasks that were waiting."
    ;;

  finish)
    [ -z "$(git status --porcelain)" ] || { echo "The main checkout has uncommitted changes. Commit or put them aside first." >&2; exit 1; }
    cur="$(git branch --show-current)"
    merged=""; waiting=""
    for branch in $(git for-each-ref --format='%(refname:short)' 'refs/heads/task/*'); do
      name="${branch#task/}"; dest="$(dest_of "$name")"
      [ -d "$dest" ] || { echo "skip $branch: no checkout at $dest"; continue; }
      if [ -n "$(git -C "$dest" status --porcelain)" ]; then
        echo "wait $name: uncommitted changes in $dest (Gate 2 not done yet)"; waiting="$waiting $name"; continue
      fi
      if [ "$(git rev-list --count "$cur..$branch")" = "0" ]; then
        base="$(cat "$(cd "$dest" && cd "$(git rev-parse --git-dir)" && pwd)/swarm-base" 2>/dev/null || true)"
        if [ -n "$base" ] && [ "$(git rev-parse "$branch")" != "$base" ]; then
          echo "already merged: $branch"; merged="$merged $name"
        else
          echo "wait $name: no commits on $branch yet"; waiting="$waiting $name"
        fi
        continue
      fi
      if git merge --no-edit "$branch" >/dev/null 2>&1; then
        echo "merged $branch"; merged="$merged $name"
      else
        echo
        echo "CONFLICT merging $branch. Stopped; nothing was removed." >&2
        git diff --name-only --diff-filter=U | sed 's/^/  conflict: /' >&2
        echo "Resolve the files, then:  git add <files> && git commit --no-edit   and run finish again." >&2
        echo "To back out of this merge instead:  git merge --abort" >&2
        [ -z "$merged" ] || echo "Already merged before the conflict:$merged" >&2
        exit 1
      fi
    done
    [ -n "$merged" ] || { echo "Nothing to finish."; exit 0; }

    if [ -z "${SWARM_NO_CHECK:-}" ]; then
      # the run belongs to the merge, not to any one task: keep it out of the task named in tasks/.active
      log="tasks/.swarm-merge.log"
      if [ -f tasks/.active ]; then mv tasks/.active tasks/.active.swarm; trap 'mv tasks/.active.swarm tasks/.active' EXIT; fi
      echo "running ./scripts/check.sh --full on the merged result (log: $log)"
      if ! ./scripts/check.sh --full > "$log" 2>&1; then
        tail -n 15 "$log"
        echo "check.sh --full FAILED after the merge. Checkouts are kept:$merged" >&2
        echo "Fix it as a normal task, then run finish again." >&2
        exit 1
      fi
      sed -n '/=== check summary ===/,$p' "$log"
    fi
    for name in $merged; do do_remove "$name"; done
    # shellcheck disable=SC2086
    plan_mark_done $merged
    echo
    echo "Finished:$merged"
    [ -z "$waiting" ] || echo "Still open:$waiting"
    if [ -s "$PLAN" ] && rows="$(plan_rows 2>/dev/null)"; then
      if ! printf '%s\n' "$rows" | grep -q "^todo"; then
        mv "$PLAN" "$PLAN.done"; echo "The plan is complete (kept as $PLAN.done)."
      else
        donelist=" $(printf '%s\n' "$rows" | awk -F'\t' '$1=="done"{printf "%s ", $2}')"
        ready=""
        for line in $(printf '%s\n' "$rows" | awk -F'\t' '$1=="todo"{print $2 "=" $3}'); do
          name="${line%%=*}"; deps="${line#*=}"
          [ -d "$(dest_of "$name")" ] && continue
          ok=1
          if [ "$deps" != "-" ]; then
            for d in $(printf '%s' "$deps" | tr ',' ' '); do case "$donelist" in *" $d "*) ;; *) ok="" ;; esac; done
          fi
          [ -n "$ok" ] && ready="$ready $name"
        done
        [ -z "$ready" ] || echo "Ready to start now:$ready   ->  scripts/swarm-worktree.sh launch"
      fi
    fi
    ;;
esac
