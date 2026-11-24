#!/usr/bin/env python3
"""PreToolUse guard: hard stops that must not depend on the model remembering a rule.

Usage (from .claude/settings.json):
  guard.py bash   -> blocks dangerous Bash commands (deploy, release, publish, migrations, ...)
                     and attempts to approve a contract from the agent's shell
  guard.py path   -> blocks Edit/Write on protected files, and on project code while there is
                     no valid human approval (Gate 1)

Gate 1 (path mode). Project code is writable only when one of these holds:
  - the active task (tasks/.active) has tasks/<id>/APPROVED whose sha256 matches contract.md,
    and the task has no receipt.md yet;
  - a quick approval (tasks/.quick) is unexpired and still has file budget.
Both are written by scripts/approve.sh, which only the human runs. Always writable: tasks/**
(except an approved contract.md, which is frozen) and the ungated paths (docs/** by default).
Switch: `require_approval: false` in harness.yml turns Gate 1 enforcement off.

Scope (path mode, optional per task). If the approved contract has a fenced block opened by a line
```scope with lines `ID: glob, glob`, project files outside those globs cannot be edited. The block
is part of the hashed contract, so the allow-list is the one the human approved. While
tasks/<id>/.package names one of the IDs, only that package's globs are open: the orchestrator
writes that file before it starts a worker. A contract without the block is not scope-checked.

Exit code 2 blocks the tool call and shows the message on stderr to the agent.
Anything unexpected fails open only for malformed input; a matched rule always blocks.
"""
import fnmatch
import hashlib
import json
import os
import re
import sys
import time

# Built-in hard stops: (regex, human-readable reason). Matched against the whole command.
BASH_RULES = [
    (r"\bfastlane\b", "fastlane (deploy/release tooling). Run builds via scripts/check.sh instead"),
    (r"\bxcrun\s+(altool|notarytool|stapler)\b", "App Store / notarization upload"),
    (r"\bxcodebuild\b.*-exportArchive\b", "archive export for distribution"),
    (r"\b(npm|yarn|pnpm)\s+publish\b", "package publishing"),
    (r"\bpod\s+trunk\s+push\b", "CocoaPods publishing"),
    (r"\bdocker\s+push\b", "image push"),
    (r"\bgh\s+release\b", "release creation"),
    (r"\bkubectl\s+(apply|delete|rollout|replace|patch)\b", "cluster change"),
    (r"\bhelm\s+(install|upgrade|uninstall)\b", "cluster change"),
    (r"\bterraform\s+(apply|destroy)\b", "infrastructure change"),
    (r"\bsupabase\s+db\s+(push|reset)\b", "database migration"),
    (r"\b(prisma|drizzle-kit|knex|sequelize|sequelize-cli|typeorm|alembic|flyway|liquibase)\b.*\b(migrate|upgrade|push|deploy)\b", "database migration"),
    (r"\b(rake|rails)\s+db:(migrate|rollback|reset|drop)\b", "database migration"),
    (r"\bmanage\.py\s+(migrate|flush)\b", "database migration"),
    (r"\bgit\s+push\b.*(--force|\s-f\b)", "force push"),
    (r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*\s+(/|~|\$HOME)(\s|$)", "destructive delete"),
]

# Gate 1: approving is human-only. Pattern-level, like the rules above: it stops the agent
# from approving by accident or by habit, it is not a defense against deliberate obfuscation.
APPROVAL_RULES = [
    r"\bapprove\.sh\b",
    r"\btasks/\S*APPROVED\b",
    r"\btasks/\.quick\b",
    r"(>|\btee\b|\bcp\b|\bmv\b|\btouch\b|\bln\b).*\bAPPROVED\b",
]

# Always protected from Edit/Write (globs relative to the repo root, matched case-insensitively).
BUILTIN_PROTECTED = [
    "harness.yml",
    ".claude/settings.json",
    ".claude/settings.local.json",
    ".claude/hooks/*",
    ".claude/agents/critic.md",
    ".claude/agents/contract-reviewer.md",
    "scripts/approve.sh",
    "tasks/*/APPROVED",
    "tasks/.quick",
    ".env",
    ".env.*",
    "**/.env",
    "**/.env.*",
]

# Writable without an approved contract (besides tasks/**).
BUILTIN_UNGATED = [
    "docs/*",
]


def read_list(cfg_path, key):
    """Read a simple YAML list under a top-level key (no external YAML dependency)."""
    items, active = [], False
    try:
        with open(cfg_path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                if re.match(r"^[A-Za-z_]+:", line):
                    active = line.startswith(key + ":")
                    continue
                if active:
                    m = re.match(r"^\s*-\s+(.*?)\s*$", line)
                    if m and not line.lstrip().startswith("#"):
                        val = m.group(1)
                        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                            val = val[1:-1]
                        items.append(val)
    except OSError:
        pass
    return items


def read_scalar(cfg_path, key):
    """Read a top-level `key: value` from a simple YAML file. Empty string if absent."""
    try:
        with open(cfg_path, encoding="utf-8") as fh:
            for raw in fh:
                m = re.match(r"^" + re.escape(key) + r":\s*(.*)$", raw.rstrip("\n"))
                if m:
                    return re.sub(r"\s+#.*$", "", m.group(1)).strip().strip("\"'")
    except OSError:
        pass
    return ""


def block(msg):
    sys.stderr.write("BLOCKED by harness: " + msg + "\n")
    sys.exit(2)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_scope(contract_path):
    """Work packages from the ```scope block of a contract: [(id, [globs])], in file order."""
    packages, inside = [], False
    try:
        with open(contract_path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not inside:
                    inside = line == "```scope"
                    continue
                if line.startswith("```"):
                    break
                m = re.match(r"^([A-Za-z0-9_-]+):\s*(.+)$", line)
                if m:
                    globs = [g.strip().strip("`\"'") for g in m.group(2).split(",")]
                    globs = [g for g in globs if g]
                    if globs:
                        packages.append((m.group(1), globs))
    except OSError:
        pass
    return packages


def scope_check(root, task, rel):
    """(ok, reason). ok is True when the contract has no scope block or `rel` is inside the open globs."""
    tdir = os.path.join(root, "tasks", task)
    packages = read_scope(os.path.join(tdir, "contract.md"))
    if not packages:
        return True, ""
    try:
        with open(os.path.join(tdir, ".package"), encoding="utf-8") as fh:
            active = fh.read().strip()
    except OSError:
        active = ""
    if active:
        chosen = [(pid, globs) for pid, globs in packages if pid == active]
        if not chosen:
            return False, "tasks/%s/.package names '%s', which is not a package of the approved contract" % (task, active)
        where = "work package %s" % active
    else:
        chosen, where = packages, "the approved scope"
    for _, globs in chosen:
        for pat in globs:
            if fnmatch.fnmatchcase(rel, pat):
                return True, ""
    allowed = ", ".join(g for _, globs in chosen for g in globs)
    return False, "it is outside %s of task %s (open there: %s)" % (where, task, allowed)


def active_task(root):
    try:
        with open(os.path.join(root, "tasks", ".active"), encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def task_approval(root):
    """Is the active task's contract approved by the human, unchanged since, and unfinished?"""
    task = active_task(root)
    if not task:
        return False, "there is no active task (tasks/.active is empty or missing)"
    if not re.match(r"^[\w.-]+$", task) or task in (".", ".."):
        return False, "tasks/.active does not name a task directory"
    tdir = os.path.join(root, "tasks", task)
    contract = os.path.join(tdir, "contract.md")
    if not os.path.isfile(contract):
        return False, "tasks/%s/contract.md does not exist" % task
    if os.path.exists(os.path.join(tdir, "receipt.md")):
        return False, "task %s already has a receipt, so it is finished" % task
    try:
        with open(os.path.join(tdir, "APPROVED"), encoding="utf-8") as fh:
            stamp = fh.read()
    except OSError:
        return False, "the contract of task %s is not approved" % task
    m = re.search(r"^sha256:\s*([0-9a-f]{64})\s*$", stamp, re.M)
    if not m:
        return False, "tasks/%s/APPROVED is malformed" % task
    try:
        current = sha256_file(contract)
    except OSError:
        return False, "tasks/%s/contract.md cannot be read" % task
    if m.group(1) != current:
        return False, "tasks/%s/contract.md changed after it was approved, so the approval no longer holds" % task
    return True, ""


def quick_approval(root, rel):
    """Quick lane: a human-granted, time-limited budget of N files without a contract."""
    path = os.path.join(root, "tasks", ".quick")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        limit = int(data.get("max_files", 0))
        expires = float(data.get("expires", 0))
        files = list(data.get("files") or [])
    except (OSError, ValueError, TypeError, AttributeError):
        return False, ""
    if time.time() > expires:
        return False, "the quick approval has expired"
    if rel in files:
        return True, ""
    if len(files) >= limit:
        return False, "the quick approval is used up (%d of %d files)" % (len(files), limit)
    files.append(rel)
    data["files"] = files
    try:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)
    except OSError:
        return False, "the quick approval could not be updated"
    return True, ""


def gate1(root, cfg, rel):
    """Block edits of project code while no human approval is in force."""
    if read_scalar(cfg, "require_approval").lower() in ("false", "no", "off", "0"):
        return
    parts = rel.split("/")
    if parts[0] == "tasks":
        if len(parts) == 3 and parts[2] == "contract.md" \
                and os.path.exists(os.path.join(root, "tasks", parts[1], "APPROVED")):
            block(
                "%s is approved and frozen. If the contract has to change, describe the change in "
                "state.md and ask the human: they edit it and approve again." % rel
            )
        return
    for pat in BUILTIN_UNGATED + read_list(cfg, "ungated_paths"):
        if fnmatch.fnmatchcase(rel, pat):
            return
    ok, why = task_approval(root)
    scope_block = False
    if ok:
        ok, why = scope_check(root, active_task(root), rel)
        if ok:
            return
        scope_block = True
    ok, quick_why = quick_approval(root, rel)
    if ok:
        return
    if scope_block:
        block(
            "Scope: %s cannot be edited, because %s. The scope is part of the approved contract. If the task "
            "really needs this file, stop and say so: the human widens the contract and approves again, or "
            "grants a quick approval. Do not look for another way to write the file." % (rel, why)
        )
    if quick_why:
        why = why + "; " + quick_why
    block(
        "Gate 1: %s cannot be edited, because %s. Project code stays locked until the human runs "
        "./scripts/approve.sh in their own terminal (or ./scripts/approve.sh --quick for a small "
        "change without a contract). You cannot approve it yourself. Stop and ask the human." % (rel, why)
    )


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)  # malformed input: nothing to judge
    tool_input = data.get("tool_input") or {}
    root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    cfg = os.path.join(root, "harness.yml")

    if mode == "bash":
        cmd = tool_input.get("command", "") or ""
        for pattern in APPROVAL_RULES:
            if re.search(pattern, cmd):
                block(
                    "approving a contract is the human's action (Gate 1). Do not run approve.sh and do "
                    "not create or change approval files. Stop and ask the human to run "
                    "./scripts/approve.sh in their own terminal."
                )
        rules = list(BASH_RULES) + [(p, "blocked_commands in harness.yml") for p in read_list(cfg, "blocked_commands")]
        for pattern, reason in rules:
            try:
                hit = re.search(pattern, cmd)
            except re.error:
                continue
            if hit:
                block(
                    f"{reason}. This is a hard stop (deploy / release / migration class). "
                    "Finish the preparation, list it under APPROVAL NEEDED in the receipt, and stop. "
                    "The human runs it."
                )
    elif mode == "path":
        target = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if not target:
            sys.exit(0)
        abs_target = os.path.realpath(target if os.path.isabs(target) else os.path.join(root, target))
        abs_root = os.path.realpath(root)
        if abs_target.startswith(abs_root + os.sep):
            rel = os.path.relpath(abs_target, abs_root).replace(os.sep, "/")
        else:
            block(f"path outside the project workspace: {target}")
        patterns = BUILTIN_PROTECTED + read_list(cfg, "protected_paths")
        low = rel.lower()
        for pat in patterns:
            p = pat.lower()
            if fnmatch.fnmatchcase(low, p) or fnmatch.fnmatchcase("/" + low, p):
                block(
                    f"{rel} is protected (matches '{pat}'). "
                    "If the change is really needed, describe it in state.md and ask the human to make it."
                )
        gate1(abs_root, cfg, rel)
    sys.exit(0)


if __name__ == "__main__":
    main()
