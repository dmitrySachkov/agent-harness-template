#!/usr/bin/env python3
"""Synthetic tests for guard.py (Gate 1 + protected paths) and scripts/approve.sh.

Run from anywhere:  python3 .claude/hooks/test_guard.py
Each case builds a throwaway project in a temp dir, feeds guard.py the JSON that Claude Code
sends to a PreToolUse hook, and checks the exit code (0 = allowed, 2 = blocked).
approve.sh is run on a pseudo-terminal, because it refuses to run without one.
"""
import hashlib
import json
import os
import pty
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
GUARD = os.path.join(HERE, "guard.py")
APPROVE = os.path.join(REPO, "scripts", "approve.sh")
TASK = "2026-01-01-demo"

CONTRACT = """---
status: DRAFT        # set by ./scripts/approve.sh
model: default
id: demo
---

# Contract: demo

## Objective
Add a thing.
"""

results = []


def make_project(harness=""):
    root = tempfile.mkdtemp(prefix="guard-test-")
    os.makedirs(os.path.join(root, "tasks", TASK))
    os.makedirs(os.path.join(root, "scripts"))
    os.makedirs(os.path.join(root, "Sources"))
    os.makedirs(os.path.join(root, "docs"))
    shutil.copy(APPROVE, os.path.join(root, "scripts", "approve.sh"))
    os.chmod(os.path.join(root, "scripts", "approve.sh"), 0o755)
    with open(os.path.join(root, "harness.yml"), "w", encoding="utf-8") as fh:
        fh.write("name: demo\n" + harness)
    with open(os.path.join(root, "tasks", TASK, "contract.md"), "w", encoding="utf-8") as fh:
        fh.write(CONTRACT)
    return root


def set_active(root, task=TASK):
    with open(os.path.join(root, "tasks", ".active"), "w", encoding="utf-8") as fh:
        fh.write(task + "\n")


def clean_env(root):
    env = dict(os.environ)
    env.pop("CLAUDECODE", None)
    env["CLAUDE_PROJECT_DIR"] = root
    return env


def guard(root, mode, tool_input):
    p = subprocess.run(
        [sys.executable, GUARD, mode],
        input=json.dumps({"tool_input": tool_input, "cwd": root}),
        capture_output=True, text=True, env=clean_env(root),
    )
    return p.returncode, p.stderr.strip()


def edit(root, rel):
    return guard(root, "path", {"file_path": os.path.join(root, rel)})


def bash(root, cmd):
    return guard(root, "bash", {"command": cmd})


def approve(root, *args, tty=True, extra_env=None):
    """Run scripts/approve.sh. With tty=True it gets a pseudo-terminal, like a human's shell."""
    env = clean_env(root)
    env.update(extra_env or {})
    cmd = [os.path.join(root, "scripts", "approve.sh")] + list(args)
    if not tty:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env)
        return p.returncode
    master, slave = pty.openpty()
    p = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
    os.close(slave)
    try:
        while True:
            if not os.read(master, 4096):
                break
    except OSError:
        pass
    os.close(master)
    return p.wait()


def check(name, got, want):
    ok = got == want
    results.append(ok)
    print("%s  %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   (got %r, want %r)" % (got, want)))


ALLOW, BLOCK = 0, 2

# --- Gate 1: project code needs an approved contract --------------------------------------
r = make_project()
check("no active task: code edit blocked", edit(r, "Sources/A.swift")[0], BLOCK)
set_active(r)
check("DRAFT contract: code edit blocked", edit(r, "Sources/A.swift")[0], BLOCK)
check("DRAFT contract: agent may still edit the contract", edit(r, "tasks/%s/contract.md" % TASK)[0], ALLOW)
check("DRAFT contract: state.md editable", edit(r, "tasks/%s/state.md" % TASK)[0], ALLOW)
check("DRAFT contract: docs/ editable (ungated)", edit(r, "docs/architecture.md")[0], ALLOW)
check("tasks/.active editable", edit(r, "tasks/.active")[0], ALLOW)

# self-approval attempts
path = os.path.join(r, "tasks", TASK, "contract.md")
open(path, "w", encoding="utf-8").write(CONTRACT.replace("DRAFT", "APPROVED"))
check("agent writes status: APPROVED itself: code still blocked", edit(r, "Sources/A.swift")[0], BLOCK)
open(path, "w", encoding="utf-8").write(CONTRACT)
check("agent cannot Write tasks/<id>/APPROVED", edit(r, "tasks/%s/APPROVED" % TASK)[0], BLOCK)
check("agent cannot Write tasks/<id>/APPROVED-CHANGES", edit(r, "tasks/%s/APPROVED-CHANGES" % TASK)[0], BLOCK)
check("bash: redirect into tasks/<id>/APPROVED-CHANGES blocked", bash(r, "echo x >> tasks/%s/APPROVED-CHANGES" % TASK)[0], BLOCK)
check("agent cannot Write tasks/<id>/approved (case variant)", edit(r, "tasks/%s/approved" % TASK)[0], BLOCK)
check("agent cannot Write tasks/.quick", edit(r, "tasks/.quick")[0], BLOCK)
check("agent cannot edit scripts/approve.sh", edit(r, "scripts/approve.sh")[0], BLOCK)
check("bash: ./scripts/approve.sh blocked", bash(r, "./scripts/approve.sh")[0], BLOCK)
check("bash: bash scripts/approve.sh --quick blocked", bash(r, "bash scripts/approve.sh --quick 3")[0], BLOCK)
check("bash: redirect into tasks/<id>/APPROVED blocked", bash(r, "echo x > tasks/%s/APPROVED" % TASK)[0], BLOCK)
check("bash: cd + touch APPROVED blocked", bash(r, "cd tasks/%s && touch APPROVED" % TASK)[0], BLOCK)
check("bash: writing tasks/.quick blocked", bash(r, "echo '{}' > tasks/.quick")[0], BLOCK)
check("bash: git status still allowed", bash(r, "git status --porcelain")[0], ALLOW)
check("bash: check.sh still allowed", bash(r, "./scripts/check.sh --full")[0], ALLOW)
check("bash: fastlane still blocked (old rule)", bash(r, "fastlane beta")[0], BLOCK)
check("approve.sh without a terminal refuses", approve(r, tty=False) != 0, True)
check("approve.sh refuses when CLAUDECODE is set", approve(r, extra_env={"CLAUDECODE": "1"}) != 0, True)
check("after refused approvals: no APPROVED file", os.path.exists(os.path.join(r, "tasks", TASK, "APPROVED")), False)

# human approves
check("approve.sh on a terminal succeeds", approve(r), 0)
text = open(path, encoding="utf-8").read()
check("approve.sh set status: APPROVED and kept the comment",
      "status: APPROVED        # set by ./scripts/approve.sh" in text, True)
stamp = open(os.path.join(r, "tasks", TASK, "APPROVED"), encoding="utf-8").read()
check("APPROVED holds the sha256 of contract.md",
      hashlib.sha256(open(path, "rb").read()).hexdigest() in stamp, True)
check("approved: code edit allowed", edit(r, "Sources/A.swift")[0], ALLOW)
check("approved: relative path allowed", guard(r, "path", {"file_path": "Sources/B.swift"})[0], ALLOW)
check("approved: contract.md is frozen", edit(r, "tasks/%s/contract.md" % TASK)[0], BLOCK)
check("approved: harness.yml still protected", edit(r, "harness.yml")[0], BLOCK)
check("approved: hooks still protected", edit(r, ".claude/hooks/guard.py")[0], BLOCK)
check("approved: path outside the project blocked", guard(r, "path", {"file_path": "/tmp/outside.txt"})[0], BLOCK)
check("approved: NotebookEdit path handled", guard(r, "path", {"notebook_path": os.path.join(r, "nb.ipynb")})[0], ALLOW)

# contract changed behind the hook's back (e.g. sed through Bash)
open(path, "a", encoding="utf-8").write("\n## Scope (in)\n- everything\n")
code, msg = edit(r, "Sources/A.swift")
check("contract changed after approval: code edit blocked", code, BLOCK)
check("... and the message says why", "changed after it was approved" in msg, True)
check("human re-approves the changed contract", approve(r), 0)
check("re-approved: code edit allowed again", edit(r, "Sources/A.swift")[0], ALLOW)

# receipt ends the approval
open(os.path.join(r, "tasks", TASK, "receipt.md"), "w").write("# Receipt\n")
check("receipt exists: code edit blocked again", edit(r, "Sources/A.swift")[0], BLOCK)
os.remove(os.path.join(r, "tasks", TASK, "receipt.md"))

# revoke
check("approve.sh --revoke succeeds", approve(r, "--revoke"), 0)
check("revoked: code edit blocked", edit(r, "Sources/A.swift")[0], BLOCK)
check("revoked: status is DRAFT again", "status: DRAFT" in open(path, encoding="utf-8").read(), True)
check("revoked: contract editable again", edit(r, "tasks/%s/contract.md" % TASK)[0], ALLOW)

# switching tasks/.active to an unapproved task does not help
os.makedirs(os.path.join(r, "tasks", "other"))
open(os.path.join(r, "tasks", "other", "contract.md"), "w").write(CONTRACT)
approve(r)
set_active(r, "other")
check("active switched to an unapproved task: blocked", edit(r, "Sources/A.swift")[0], BLOCK)
set_active(r, "../..")
check("tasks/.active with a path instead of a name: blocked", edit(r, "Sources/A.swift")[0], BLOCK)
shutil.rmtree(r)

# --- quick lane ----------------------------------------------------------------------------
r = make_project()
check("quick: --quick 2 succeeds", approve(r, "--quick", "2"), 0)
check("quick: 1st file allowed", edit(r, "Sources/A.swift")[0], ALLOW)
check("quick: same file again allowed", edit(r, "Sources/A.swift")[0], ALLOW)
check("quick: 2nd file allowed", edit(r, "Sources/B.swift")[0], ALLOW)
code, msg = edit(r, "Sources/C.swift")
check("quick: 3rd file blocked", code, BLOCK)
check("... and the message says the budget is used up", "used up" in msg, True)
check("quick: protected paths stay protected", edit(r, "harness.yml")[0], BLOCK)
q = json.load(open(os.path.join(r, "tasks", ".quick")))
q["expires"] = int(time.time()) - 5
q["files"] = []
json.dump(q, open(os.path.join(r, "tasks", ".quick"), "w"))
check("quick: expired approval blocks", edit(r, "Sources/A.swift")[0], BLOCK)
check("quick: --quick 99 refused (needs a contract)", approve(r, "--quick", "99") != 0, True)
check("quick: --revoke removes it", approve(r, "--revoke") == 0 and not os.path.exists(os.path.join(r, "tasks", ".quick")), True)
shutil.rmtree(r)

# --- harness.yml switches --------------------------------------------------------------------
r = make_project("require_approval: false\n")
check("require_approval: false -> code edit allowed without a contract", edit(r, "Sources/A.swift")[0], ALLOW)
check("require_approval: false -> protected paths still protected", edit(r, "harness.yml")[0], BLOCK)
shutil.rmtree(r)

r = make_project("require_approval: true\nungated_paths:\n  - \"README.md\"\n  - \"notes/*\"\nprotected_paths:\n  - \"**/Generated/**\"\n")
check("ungated_paths: README.md editable without a contract", edit(r, "README.md")[0], ALLOW)
check("ungated_paths: notes/x.md editable", edit(r, "notes/x.md")[0], ALLOW)
check("ungated_paths: other code still blocked", edit(r, "Sources/A.swift")[0], BLOCK)
check("protected_paths from harness.yml still work", edit(r, "Sources/Generated/A.swift")[0], BLOCK)
shutil.rmtree(r)

r = make_project()  # harness.yml without the new keys (project made from an older template)
check("old harness.yml (no require_approval key): Gate 1 is on", edit(r, "Sources/A.swift")[0], BLOCK)
shutil.rmtree(r)

# --- scope: work packages from the approved contract -----------------------------------------
SCOPED = CONTRACT + """
## Work packages
```scope
# comment lines and blank lines are ignored

P1: Sources/Domain/*.swift
P2: Sources/Data/Store.swift, `Tests/StoreTests.swift`
```
- P1: the port
"""


def scoped_project():
    root = make_project()
    with open(os.path.join(root, "tasks", TASK, "contract.md"), "w", encoding="utf-8") as fh:
        fh.write(SCOPED)
    set_active(root)
    return root


def set_package(root, value):
    with open(os.path.join(root, "tasks", TASK, ".package"), "w", encoding="utf-8") as fh:
        fh.write(value)


r = scoped_project()
check("scope: not approved yet -> blocked as before", edit(r, "Sources/Domain/Port.swift")[0], BLOCK)
check("scope: approve the contract with packages", approve(r), 0)
check("scope: file of P1 allowed", edit(r, "Sources/Domain/Port.swift")[0], ALLOW)
check("scope: file of P2 allowed (no active package: union)", edit(r, "Sources/Data/Store.swift")[0], ALLOW)
check("scope: glob written in backticks works", edit(r, "Tests/StoreTests.swift")[0], ALLOW)
code, msg = edit(r, "Sources/App/Root.swift")
check("scope: file outside every package blocked", code, BLOCK)
check("... and the message says it is a scope block", msg.startswith("BLOCKED by harness: Scope:") and "approved scope" in msg, True)
check("scope: tasks/ still open", edit(r, "tasks/%s/state.md" % TASK)[0], ALLOW)
check("scope: docs/ still open", edit(r, "docs/architecture.md")[0], ALLOW)
check("scope: the agent may set tasks/<id>/.package", edit(r, "tasks/%s/.package" % TASK)[0], ALLOW)
set_package(r, "P1\n")
check("active P1: its file allowed", edit(r, "Sources/Domain/Port.swift")[0], ALLOW)
code, msg = edit(r, "Sources/Data/Store.swift")
check("active P1: a file of P2 blocked", code, BLOCK)
check("... and the message names the package", "work package P1" in msg, True)
set_package(r, "P2")
check("active P2: its file allowed", edit(r, "Sources/Data/Store.swift")[0], ALLOW)
check("active P2: a file of P1 blocked", edit(r, "Sources/Domain/Port.swift")[0], BLOCK)
set_package(r, "P9")
check("unknown active package: everything in scope blocked", edit(r, "Sources/Domain/Port.swift")[0], BLOCK)
set_package(r, "\n")
check("empty .package: back to the union", edit(r, "Sources/Data/Store.swift")[0], ALLOW)
check("scope: contract is frozen, the agent cannot widen it", edit(r, "tasks/%s/contract.md" % TASK)[0], BLOCK)
with open(os.path.join(r, "tasks", TASK, "contract.md"), "a", encoding="utf-8") as fh:
    fh.write("\n```scope\nP3: Sources/App/*\n```\n")
check("scope widened behind the hook's back: approval void, blocked", edit(r, "Sources/Domain/Port.swift")[0], BLOCK)
approve(r)
check("quick approval lets the human open one file outside the scope", approve(r, "--quick", "1"), 0)
check("... that file is allowed", edit(r, "Sources/App/Root.swift")[0], ALLOW)
check("... a second file outside the scope is blocked", edit(r, "Sources/App/Other.swift")[0], BLOCK)
check("... in-scope files do not spend the quick budget", edit(r, "Sources/Domain/Port.swift")[0], ALLOW)
shutil.rmtree(r)

r = make_project()
with open(os.path.join(r, "tasks", TASK, "contract.md"), "w", encoding="utf-8") as fh:
    fh.write(CONTRACT + "\n## Work packages\n```scope\n```\n")
set_active(r)
approve(r)
check("empty scope block: no scope check, any project file allowed", edit(r, "Sources/App/Root.swift")[0], ALLOW)
shutil.rmtree(r)

r = scoped_project()
with open(os.path.join(r, "harness.yml"), "a", encoding="utf-8") as fh:
    fh.write("protected_paths:\n  - \"Sources/Domain/Generated.swift\"\n")
approve(r)
check("scope does not unlock protected paths", edit(r, "Sources/Domain/Generated.swift")[0], BLOCK)
shutil.rmtree(r)

print()
print("%d passed, %d failed" % (results.count(True), results.count(False)))
sys.exit(0 if all(results) else 1)
