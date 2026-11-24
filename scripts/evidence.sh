#!/usr/bin/env bash
# Evidence matcher. For every acceptance item of a task contract it lists the tests the contract names
# (in backticks, like `testHeaderLines` or `HeaderTests.testHeaderLines`) and says where each one passed in
# checks.log, and whether that proof is for the code the LAST run was made on. Read-only: it writes nothing.
# Usage: scripts/evidence.sh [task-dir-name]     default: the task named in tasks/.active
# Exit 0: every named test has a passing line on the current build. Exit 1: a named test is MISSING, FAILED or
# has proof only from an OLDER build, or the log cannot decide. Exit 2: usage error.
# How "current build" works: check.sh starts a run with `# check run <time> full=<n> head=<rev> work=<fingerprint>`.
# A result line counts as current when it sits in a run (the run header up to the next header, appended greps and
# red runs included) whose work= equals the work= of the last run. Of the current lines the LAST one decides, so a
# red run followed by the green run ends as passed. A pass seen only under another work= is OLDER BUILD: the code
# changed after it, so it proves nothing about the current code.
# Limits, on purpose: it reads XCTest lines (`Test Case '-[Module.Class testName]' passed|failed`); it does not
# judge proofs that are a command, a measure or a manual result (listed BY HAND); PASS means only that the named
# tests passed. check.sh keeps only the tail of each step's output, so per-test lines of a large test target must
# be appended to checks.log (a grep of the full output, with its command) for this to see them.
set -u
cd "$(dirname "$0")/.." || exit 2
ARG="${1:-}"
if [ -z "$ARG" ]; then
  [ -f tasks/.active ] || { echo "evidence.sh: no task named and tasks/.active is missing" >&2; exit 2; }
  ARG="$(head -1 tasks/.active | tr -d '[:space:]')"
fi
ARG="${ARG#tasks/}"; ARG="${ARG%/}"
T="tasks/$ARG"
[ -f "$T/contract.md" ] || { echo "evidence.sh: $T/contract.md not found" >&2; exit 2; }
[ -f "$T/checks.log" ] || { echo "evidence.sh: $T/checks.log not found: run ./scripts/check.sh --full first" >&2; exit 1; }

python3 - "$T" <<'PY'
import re, sys

t = sys.argv[1]
contract = open(f"{t}/contract.md", encoding="utf-8").read().splitlines()
log = open(f"{t}/checks.log", encoding="utf-8", errors="replace").read().splitlines()

# runs: header line index -> work fingerprint
hdr = [(i, (re.search(r"work=(\S+)", l) or [None, "n/a"])[1]) for i, l in enumerate(log) if l.startswith("# check run")]
if not hdr:
    print(f"evidence.sh: {t}/checks.log has no '# check run' section")
    sys.exit(1)
last_i, last_work = hdr[-1]
print(f"evidence.sh: {t}")
print(f"last run: {log[last_i].strip()} (log line {last_i + 1})")

def run_of(lineno):  # index into hdr of the run that line belongs to, or None before the first run
    k = None
    for n, (i, _) in enumerate(hdr):
        if i <= lineno:
            k = n
        else:
            break
    return k

def current(k):
    return k is not None and (last_work == "n/a" or hdr[k][1] == last_work)

pat = re.compile(r"Test Case '-\[(?:\S+\.)?(\w+) (\w+)\]' (passed|failed)")
res = []  # (lineno, class, test, status, run index)
for i, l in enumerate(log):
    m = pat.search(l)
    if m:
        res.append((i, m.group(1), m.group(2), m.group(3), run_of(i)))
undecided = not res

items, cur, inside = [], None, False
for l in contract:
    if l.startswith("## "):
        inside = l.lower().startswith("## acceptance")
        cur = None
        continue
    if not inside:
        continue
    m = re.match(r"^- \[[ xX]\]\s*(\S+)", l)
    if m:
        cur = [m.group(1).rstrip(".,:;"), l]
        items.append(cur)
    elif cur and l.strip() and not l.startswith("- ") and not l.startswith("#"):
        cur[1] += " " + l.strip()

name_pat = re.compile(r"(?:(\w+)\.)?(test[A-Z0-9_]\w*)(?:\(\))?")

def judge(cls, name):
    hits = [r for r in res if r[2] == name and (cls is None or r[1] == cls)]
    if undecided:
        return "bad", "UNDECIDED: no XCTest result lines in checks.log"
    now = [r for r in hits if current(r[4])]
    if now:
        r = max(now, key=lambda x: x[0])
        if r[3] == "passed":
            return "ok", f"passed (checks.log:{r[0] + 1})"
        return "bad", f"FAILED in the current build (checks.log:{r[0] + 1})"
    if hits:
        r = max(hits, key=lambda x: x[0])
        w = hdr[r[4]][1] if r[4] is not None else "?"
        return "bad", f"OLDER BUILD: {r[3]} at checks.log:{r[0] + 1} under work={w}, the last run is work={last_work}"
    return "bad", "MISSING: no result line in checks.log"

tested = by_hand = bad_items = 0
out = []
for iid, text in items:
    names = []
    for span in re.findall(r"`([^`]+)`", text):
        m = name_pat.fullmatch(span.strip())
        if m and (m.group(1), m.group(2)) not in names:
            names.append((m.group(1), m.group(2)))
    if not names:
        by_hand += 1
        out.append(f"{iid:<5} BY HAND  no named test: a command, a measure or a manual result, check it yourself")
        continue
    tested += 1
    verdicts = [judge(c, n) for c, n in names]
    nbad = sum(1 for v, _ in verdicts if v == "bad")
    if nbad:
        bad_items += 1
        out.append(f"{iid:<5} PROBLEM  {len(names) - nbad} of {len(names)} named tests proven on the current build")
    else:
        out.append(f"{iid:<5} PASS     {len(names)} named test(s) passed on the current build")
    for (c, n), (v, why) in zip(names, verdicts):
        out.append(f"        {n}: {why}")

print("\n".join(out))
print(f"summary: {len(items)} item(s); {tested} with named tests ({tested - bad_items} proven, {bad_items} not); {by_hand} by hand")
print("PASS means only that the named tests passed; commands, measures and manual results in the same item are not judged here.")
sys.exit(1 if bad_items or not items else 0)
PY
