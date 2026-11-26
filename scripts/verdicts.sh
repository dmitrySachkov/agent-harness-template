#!/usr/bin/env bash
# Verdict summary for the harness audit. Read-only: it writes nothing.
# Usage: scripts/verdicts.sh [--since YYYY-MM-DD]
# For every task under tasks/ (the date prefix of the folder name decides --since) it reads verdict.attempt-<N>.md
# (or verdict.md when there are no numbered copies) and prints: one line per task (rounds, REJECTs, blockers,
# majors), totals, every blocker line with its task and round, and a count of the hook's blocks from
# tasks/.guard.log by rule. It does not classify: grouping the blockers by cause is the reader's job (/audit).
set -u
cd "$(dirname "$0")/.." || exit 2
SINCE=""
if [ "${1:-}" = "--since" ]; then SINCE="${2:-}"; fi
python3 - "$SINCE" <<'PY'
import glob, json, os, re, sys
since = sys.argv[1]
rows, blockers = [], []
for tdir in sorted(glob.glob("tasks/*/")):
    name = os.path.basename(tdir.rstrip("/"))
    m = re.match(r"(\d{4}-\d{2}-\d{2})-", name)
    if not m or (since and m.group(1) < since):
        continue
    files = sorted(glob.glob(tdir + "verdict.attempt-*.md"), key=lambda p: int(re.search(r"attempt-(\d+)", p).group(1)))
    last = tdir + "verdict.md"
    if os.path.exists(last):
        # the final verdict is a round of its own unless it is the same text as the last numbered copy
        if not files or open(files[-1], encoding="utf-8", errors="replace").read().strip() != open(last, encoding="utf-8", errors="replace").read().strip():
            files.append(last)
    if not files:
        continue
    rej = nb = nm = 0
    for f in files:
        text = open(f, encoding="utf-8", errors="replace").read()
        rnd = re.search(r"attempt-(\d+)", f)
        rnd = rnd.group(1) if rnd else "last"
        if re.search(r"^VERDICT:\s*REJECT", text, re.M):
            rej += 1
        for l in text.splitlines():
            if re.match(r"^\s*[-*]\s*\[blocker\]", l, re.I):
                nb += 1
                blockers.append((name, rnd, re.sub(r"^\s*[-*]\s*\[blocker\]\s*", "", l, flags=re.I)[:240]))
            elif re.match(r"^\s*[-*]\s*\[major\]", l, re.I):
                nm += 1
    rows.append((name, len(files), rej, nb, nm, os.path.exists(tdir + "receipt.md")))
print("verdicts.sh%s" % (" since " + since if since else ""))
print("%-44s %6s %7s %8s %6s %s" % ("task", "rounds", "REJECT", "blocker", "major", "receipt"))
for r in rows:
    print("%-44s %6d %7d %8d %6d %s" % (r[0], r[1], r[2], r[3], r[4], "yes" if r[5] else "no"))
n = len(rows)
print("\ntotal: %d task(s) with a verdict; %d with at least one REJECT; %d REJECT round(s); %d blocker(s); %d major(s)"
      % (n, sum(1 for r in rows if r[2]), sum(r[2] for r in rows), sum(r[3] for r in rows), sum(r[4] for r in rows)))
if n and not any(r[1] > 1 for r in rows):
    print("note: no numbered verdict copies found; only the last verdict of each task is counted")
print("\nBLOCKERS (task, round, text):")
for b in blockers:
    print("- %s r%s: %s" % b)
if not blockers:
    print("- none")
print("\nHOOK BLOCKS (tasks/.guard.log):")
log = "tasks/.guard.log"
if not os.path.exists(log):
    print("- no log yet")
else:
    by, total = {}, 0
    for l in open(log, encoding="utf-8", errors="replace"):
        try:
            rec = json.loads(l)
        except ValueError:
            continue
        if since and rec.get("at", "")[:10] < since:
            continue
        total += 1
        key = (rec.get("mode", "?"), rec.get("why", "")[:70])
        by[key] = by.get(key, 0) + 1
    print("- %d block(s)" % total)
    for (mode, why), c in sorted(by.items(), key=lambda x: -x[1]):
        print("  %4d  %-5s %s" % (c, mode, why))
PY
