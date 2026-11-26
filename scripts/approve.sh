#!/usr/bin/env bash
# Gate 1: the HUMAN approves a task contract. The agent cannot run this (hook + deny + TTY check).
# Usage (in your own terminal, not through the agent and not via `!` in Claude Code):
#   scripts/approve.sh [task-dir-name]   approve the contract (default: the task in tasks/.active)
#   scripts/approve.sh --quick [N]       allow a small change without a contract: up to N files (default 3), 60 minutes
#   scripts/approve.sh --revoke [task]   withdraw the approval (and any quick approval)
#   scripts/approve.sh --status          show what is approved right now
#   scripts/approve.sh --change [task]   accept entries of "## CONTRACT CHANGES" in state.md (asks about each one)
# Approving sets `status: APPROVED` in contract.md and writes tasks/<id>/APPROVED with the sha256
# of the contract. .claude/hooks/guard.py lets the agent edit project code only while that hash
# matches, so any later change of the contract needs a new approval.
set -eu

MODE=approve
ARG=""
case "${1:-}" in
  --quick)  MODE=quick;  ARG="${2:-3}" ;;
  --revoke) MODE=revoke; ARG="${2:-}" ;;
  --status) MODE=status ;;
  --change) MODE=change; ARG="${2:-}" ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  -*) echo "unknown argument: $1" >&2; exit 64 ;;
  *) ARG="${1:-}" ;;
esac
cd "$(dirname "$0")/.."

if [ "$MODE" != "status" ]; then
  if [ -n "${CLAUDECODE:-}" ] || [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "approve.sh: approval is a human action. Run it yourself in your own terminal." >&2
    exit 1
  fi
fi

active_task() {
  [ -f tasks/.active ] && tr -d '[:space:]' < tasks/.active || true
}

if [ "$MODE" = "quick" ]; then
  case "$ARG" in ''|*[!0-9]*) echo "--quick takes a number of files, got: $ARG" >&2; exit 64 ;; esac
  [ "$ARG" -ge 1 ] && [ "$ARG" -le 10 ] || { echo "--quick: 1 to 10 files. Anything bigger needs a contract (/task)." >&2; exit 64; }
  mkdir -p tasks
  python3 - "$ARG" <<'PY'
import json, sys, time
now = time.time()
data = {"max_files": int(sys.argv[1]), "created": int(now), "expires": int(now) + 3600, "files": []}
with open("tasks/.quick", "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
  echo "Quick approval: up to $ARG file(s), valid for 60 minutes, no contract and no critic."
  echo "Withdraw early with: scripts/approve.sh --revoke"
  exit 0
fi

if [ "$MODE" = "status" ]; then
  python3 - "$(active_task)" <<'PY'
import hashlib, json, os, re, sys, time
task = sys.argv[1]
if not task:
    print("active task: none")
else:
    tdir = os.path.join("tasks", task)
    contract = os.path.join(tdir, "contract.md")
    stamp = os.path.join(tdir, "APPROVED")
    state = "NOT APPROVED"
    if not os.path.isfile(contract):
        state = "no contract.md"
    elif os.path.isfile(stamp):
        m = re.search(r"^sha256:\s*([0-9a-f]{64})\s*$", open(stamp, encoding="utf-8").read(), re.M)
        cur = hashlib.sha256(open(contract, "rb").read()).hexdigest()
        state = "APPROVED" if m and m.group(1) == cur else "APPROVAL VOID (contract changed after approval)"
    if os.path.exists(os.path.join(tdir, "receipt.md")):
        state += ", finished (receipt exists): code is locked again"
    print("active task: %s -> %s" % (task, state))
try:
    q = json.load(open("tasks/.quick", encoding="utf-8"))
    left = int(q["expires"] - time.time())
    if left > 0:
        print("quick approval: %d of %d file(s) used, %d min left" % (len(q.get("files") or []), q["max_files"], left // 60))
        for f in q.get("files") or []:
            print("  " + f)
    else:
        print("quick approval: expired")
except (OSError, ValueError, KeyError, TypeError):
    print("quick approval: none")
PY
  exit 0
fi

TASK="$ARG"
[ -n "$TASK" ] || TASK=$(active_task)

if [ "$MODE" = "revoke" ]; then
  rm -f tasks/.quick
  # No task named and the active one is already finished: the human meant the quick approval, not a closed task.
  if [ -z "$ARG" ] && [ -n "$TASK" ] && [ -f "tasks/$TASK/receipt.md" ]; then
    echo "Quick approval removed if there was one."
    echo "The active task $TASK is finished (receipt exists): its approval is left as it is."
    echo "To withdraw it anyway: scripts/approve.sh --revoke $TASK"
    exit 0
  fi
  if [ -n "$TASK" ] && [ -f "tasks/$TASK/APPROVED" ]; then
    rm -f "tasks/$TASK/APPROVED"
    python3 - "tasks/$TASK/contract.md" DRAFT <<'PY'
import re, sys
path, value = sys.argv[1], sys.argv[2]
try:
    lines = open(path, encoding="utf-8", newline="").read().split("\n")
except OSError:
    sys.exit(0)
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            break
        m = re.match(r"^(status:\s*)(\S+)(.*)$", lines[i])
        if m:
            lines[i] = m.group(1) + value + m.group(3)
            break
    open(path, "w", encoding="utf-8", newline="").write("\n".join(lines))
PY
    echo "Approval of $TASK withdrawn (status: DRAFT). Project code is locked."
  else
    echo "No task approval to withdraw. Quick approval removed if there was one."
  fi
  exit 0
fi

if [ "$MODE" = "change" ]; then
  [ -n "$TASK" ] || { echo "No task given and tasks/.active is empty." >&2; exit 1; }
  case "$TASK" in */*|.|..) echo "Task must be a directory name under tasks/, got: $TASK" >&2; exit 64 ;; esac
  [ -f "tasks/$TASK/state.md" ] || { echo "Not found: tasks/$TASK/state.md" >&2; exit 1; }
  python3 - "tasks/$TASK" <<'PY'
import hashlib, os, re, sys, time
tdir = sys.argv[1]

def change_entries(path):
    """Entries of '## CONTRACT CHANGES' in state.md: one per list item, continuation lines joined; 'none' skipped."""
    out, cur, inside, comment = [], None, False, False
    for l in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if l.startswith("## "):
            inside = l.strip().upper().startswith("## CONTRACT CHANGES")
            cur = None
            continue
        if not inside:
            continue
        if "<!--" in l:
            comment = True
        if comment:
            if "-->" in l:
                comment = False
            continue
        if re.match(r"^[-*]\s+\S", l):
            cur = [l.strip()]
            out.append(cur)
        elif l.strip() and cur is not None:
            cur.append(l.strip())
        else:
            cur = None
    texts = [re.sub(r"\s+", " ", " ".join(e)).strip() for e in out]
    return [x for x in texts if not re.match(r"^[-*]\s+(none|нет)\W*$", x, re.I)]

def change_hash(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

stamp = os.path.join(tdir, "APPROVED-CHANGES")
have = set()
if os.path.exists(stamp):
    have = set(re.findall(r"^sha256:\s*([0-9a-f]{64})", open(stamp, encoding="utf-8").read(), re.M))
entries = change_entries(os.path.join(tdir, "state.md"))
new = [e for e in entries if change_hash(e) not in have]
print("%s: %d entr(ies) under CONTRACT CHANGES, %d already accepted, %d to decide" % (tdir, len(entries), len(entries) - len(new), len(new)))
if not new:
    sys.exit(0)
tty = open("/dev/tty", encoding="utf-8", errors="replace")
accepted = 0
for n, e in enumerate(new, 1):
    print("\n[%d of %d]\n%s\n" % (n, len(new), e))
    sys.stdout.write("Accept this change of the contract? [y/N/q] ")
    sys.stdout.flush()
    a = tty.readline().strip().lower()
    if a in ("q", "quit"):
        break
    if a in ("y", "yes", "д", "да"):
        with open(stamp, "a", encoding="utf-8") as fh:
            fh.write("sha256: %s  accepted_at: %s  %s\n" % (change_hash(e), time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), e[:70]))
        accepted += 1
        print("accepted")
    else:
        print("NOT accepted: for the critic the contract stands as written")
print("\n%d accepted now, %d left without acceptance. File: %s" % (accepted, len(new) - accepted, stamp))
PY
  exit $?
fi

# --- approve ---
[ -n "$TASK" ] || { echo "No task given and tasks/.active is empty." >&2; exit 1; }
case "$TASK" in */*|.|..) echo "Task must be a directory name under tasks/, got: $TASK" >&2; exit 64 ;; esac
T="tasks/$TASK"
[ -f "$T/contract.md" ] || { echo "Contract not found: $T/contract.md" >&2; exit 1; }
# No task named and the active one is already finished: do not re-approve a closed task by accident.
if [ -z "$ARG" ] && [ -f "$T/receipt.md" ]; then
  echo "The active task $TASK is finished (receipt exists). Nothing was approved." >&2
  echo "Name the task you mean:  scripts/approve.sh <task-dir-name>" >&2
  for c in tasks/*/contract.md; do
    [ -f "$c" ] || continue
    d=$(dirname "$c")
    case "$d" in tasks/_TEMPLATE) continue ;; esac
    if grep -q '^status:[[:space:]]*DRAFT' "$c" && [ ! -f "$d/receipt.md" ]; then
      echo "  waiting for approval: $(basename "$d")" >&2
    fi
  done
  exit 1
fi
[ ! -f "$T/receipt.md" ] || echo "WARNING: $T/receipt.md exists. The task counts as finished and code stays locked until you remove the receipt."
if [ -f "$T/contract-review.md" ] && grep -q '^VERDICT:[[:space:]]*REVISE' "$T/contract-review.md"; then
  echo "WARNING: the contract-reviewer's last verdict is REVISE. Read $T/contract-review.md if you have not."
fi

python3 - "$T" <<'PY'
import hashlib, os, re, sys, time
tdir = sys.argv[1]
path = os.path.join(tdir, "contract.md")
lines = open(path, encoding="utf-8", newline="").read().split("\n")
if not lines or lines[0].strip() != "---":
    sys.exit("contract.md has no frontmatter (the first line must be ---)")
done = False
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        break
    m = re.match(r"^(status:\s*)(\S+)(.*)$", lines[i])
    if m:
        lines[i] = m.group(1) + "APPROVED" + m.group(3)
        done = True
        break
if not done:
    sys.exit("contract.md has no `status:` line in its frontmatter")
with open(path, "w", encoding="utf-8", newline="") as fh:
    fh.write("\n".join(lines))
digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
with open(os.path.join(tdir, "APPROVED"), "w", encoding="utf-8") as fh:
    fh.write("sha256: %s\napproved_at: %s\n" % (digest, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())))
print("sha256: " + digest)
packages, inside = [], False
for raw in lines:
    line = raw.strip()
    if not inside:
        inside = line == "```scope"
        continue
    if line.startswith("```"):
        break
    m = re.match(r"^([A-Za-z0-9_-]+):\s*(.+)$", line)
    if m:
        packages.append("%s (%d)" % (m.group(1), len([g for g in m.group(2).split(",") if g.strip()])))
if packages:
    print("Scope enforced by the hook, package (number of globs): " + ", ".join(packages))
else:
    print("No work packages in the contract: the hook does not limit which project files are edited.")
PY

if [ "$(active_task)" != "$TASK" ]; then
  echo "NOTE: tasks/.active names '$(active_task)', not '$TASK'. The agent works on the active task only."
fi
echo "Approved: $T/contract.md (status: APPROVED). The contract is frozen: edit it and run this again to change it."
