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
# tests passed. check.sh appends the per-test lines of each step's full output to checks.log ("### per-test results").
# Manual acceptance: if the task has acceptance-cases.md, every case line ("- M1.4 ... Ответ: да") is read from THAT
# file. No answer, a placeholder, or an answer that is not "да"/"yes" is a PROBLEM, whatever state.md records.
# A case that asks for a value ("Ответ (сколько секунд): 2с") is printed as VALUE and not judged.
# Scope: paths changed since the BASELINE hash in state.md (plus untracked ones) are matched against the globs in
# backticks under "must not change" in the contract and listed as SCOPE TOUCHED. Listed, not judged; no effect on exit.
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
print("PASS means only that the named tests passed; commands and measures in the same item are not judged here.")

# Manual acceptance: the human's answers, read from acceptance-cases.md and from nowhere else.
import os
man_bad = 0
mpath = f"{t}/acceptance-cases.md"
if os.path.exists(mpath):
    cases, cur = [], None  # [id, first line number, text]
    for n, l in enumerate(open(mpath, encoding="utf-8", errors="replace").read().splitlines(), 1):
        m = re.match(r"^\s*[-*]\s+\**(M\d+(?:\.\d+)*)\b", l)
        if m:
            cur = [m.group(1), n, l]
            cases.append(cur)
        elif l.startswith("#") or not l.strip():
            cur = None
        elif cur:
            cur[2] += " " + l.strip()
    yes = 0
    for cid, n, text in cases:
        marks = list(re.finditer(r"(?:Ответ|Answer)\**\s*(\([^)]*\))?\s*:", text))
        ans = text[marks[-1].end():].strip() if marks else ""
        word = re.sub(r"[\s_*`.…]+", " ", ans).strip().lower()
        if not word or "/" in word[:24]:
            man_bad += 1
            print(f"{cid:<5} PROBLEM  manual case has no answer ({mpath}:{n}); state.md cannot stand in for it")
        elif marks[-1].group(1):  # "Ответ (сколько секунд): ..." asks for a value, not for a yes
            yes += 1
            print(f"{cid:<5} VALUE    read it against the contract yourself ({mpath}:{n}): {ans[:90]}")
        elif re.match(r"(да|yes)(?![\w-])", word):
            yes += 1
        else:
            man_bad += 1
            print(f"{cid:<5} PROBLEM  manual answer is not yes ({mpath}:{n}): {ans[:90]}")
    print(f"manual: {len(cases)} case(s) in acceptance-cases.md; {yes} answered yes or with a value, {man_bad} without")
    if man_bad:
        print("A case without a yes is not met. Only the human changes an answer, in acceptance-cases.md; an accepted deviation needs a CONTRACT CHANGES entry.")

# Scope: the paths this task changed, against the globs of "## Out of scope / must not change". It lists, it does
# not judge: a contract may name an exception in prose, and this check cannot read prose. Exit code is not affected.
import fnmatch, subprocess
def _git(*a):
    try:
        r = subprocess.run(["git"] + list(a), capture_output=True, text=True)
    except OSError:
        return None
    return r.stdout.splitlines() if r.returncode == 0 else None
base = None
if os.path.exists(f"{t}/state.md"):
    for l in open(f"{t}/state.md", encoding="utf-8", errors="replace").read().splitlines():
        if "rev-parse" in l and "HEAD" in l:
            m = re.search(r"\b([0-9a-f]{7,40})\b", l.split("HEAD", 1)[1])
            base = m.group(1) if m else None
            break
globs, inside = [], False
for l in contract:
    if l.startswith("## "):
        inside = "must not change" in l.lower() or l.lower().startswith("## out of scope")
        continue
    if inside:
        for span in re.findall(r"`([^`]+)`", l):
            span = span.strip()
            if " " in span or "(" in span or span in globs:
                continue
            if "/" in span or "*" in span or re.search(r"\.\w{1,10}$", span):
                globs.append(span)
def _hit(path, g):
    g = g.rstrip("/")
    forms = [g, g + "/*"]
    if g.startswith("**/"):
        forms += [g[3:], g[3:] + "/*"]
    if any(fnmatch.fnmatchcase(path, f) for f in forms):
        return True
    return "/" not in g and any(fnmatch.fnmatchcase(part, g) for part in path.split("/"))
rev = os.environ.get("EVIDENCE_REV", "")  # for audits of a closed task: compare baseline..REV instead of the working tree
if not base:
    print("scope: NOT CHECKED, no baseline hash under BASELINE in state.md")
elif not globs:
    print("scope: NOT CHECKED, no path or glob in backticks under 'must not change' in the contract")
else:
    changed = _git("diff", "--name-status", "--no-renames", base, rev) if rev else _git("diff", "--name-status", "--no-renames", base)
    extra = [] if rev else _git("ls-files", "--others", "--exclude-standard")
    if changed is None or extra is None:
        print(f"scope: NOT CHECKED, git could not compare with baseline {base}")
    else:
        kind = {}  # path -> A (new), M (edited), D (deleted)
        for l in changed:
            f = l.split("\t")
            if len(f) == 2:
                kind[f[1]] = f[0][:1]
        for p in extra:
            if p:
                kind[p] = "A"
        paths = sorted(p for p in kind if not p.startswith(t + "/"))
        word = {"A": "SCOPE NEW    ", "D": "SCOPE DELETED", "M": "SCOPE TOUCHED"}
        seen, lines = set(), []
        for p in paths:
            for g in globs:
                if _hit(p, g):
                    seen.add(p)
                    lines.append(f"{word.get(kind[p], 'SCOPE TOUCHED')}  {p}   matches `{g}`")
                    break
        old = sum(1 for p in seen if kind[p] != "A")
        print(f"scope: baseline {base}{' .. ' + rev if rev else ' .. working tree'}; {len(paths)} path(s) changed outside the task folder; {len(globs)} glob(s) under 'must not change'; {old} existing file(s) touched or deleted, {len(seen) - old} new file(s) under a frozen glob")
        if lines:
            print("\n".join(lines))
            print("Every TOUCHED or DELETED path needs an exception the contract names, or an accepted CONTRACT CHANGES entry; without one it is a violation. NEW is a file created under a frozen glob: usually allowed, say where the contract allows it. Exceptions written in prose are not read here: check each line yourself.")

# Contract changes: an entry of "## CONTRACT CHANGES" in state.md counts only when the human accepted it
# with scripts/approve.sh --change (its sha256 is then in APPROVED-CHANGES, a file the agent cannot write).
import hashlib

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

ch_bad = 0
spath = f"{t}/state.md"
if os.path.exists(spath):
    entries = change_entries(spath)
    if entries:
        have = set()
        if os.path.exists(f"{t}/APPROVED-CHANGES"):
            have = set(re.findall(r"^sha256:\s*([0-9a-f]{64})", open(f"{t}/APPROVED-CHANGES", encoding="utf-8").read(), re.M))
        for e in entries:
            if change_hash(e) in have:
                print(f"CHANGE ACCEPTED  {e[:100]}")
            else:
                ch_bad += 1
                print(f"CHANGE PROBLEM   not accepted by the human: {e[:100]}")
        print(f"contract changes: {len(entries)} entr(ies) in state.md; {len(entries) - ch_bad} accepted, {ch_bad} not")
        if ch_bad:
            print("A change is accepted only by ./scripts/approve.sh --change in the human's own terminal. Words in the chat do not count: ask the human, and do not start the critic. An accepted entry must not be edited (the edit voids it): add a new entry.")
sys.exit(1 if bad_items or man_bad or ch_bad or not items else 0)
PY
