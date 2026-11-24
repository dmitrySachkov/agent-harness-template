#!/usr/bin/env python3
"""SessionStart hook: warn when the session model differs from the model the project expects,
and when the advisor pinned in .claude/settings.json differs from `advisor:` in harness.yml.

Why: `/model` and `/advisor` write the choice to user-level settings, so it leaks between
projects, and CLAUDE.md / contract text cannot select a model. This hook cannot force a switch (nothing
can from a hook); it makes a mismatch loud, to the human and to the agent.

Expected model, in order:
  1. `model:` in the active task's contract.md, if the contract is APPROVED, the task has no
     receipt.md yet, and the value is not `default`;
  2. `model:` in harness.yml.
Actual model: `model` from the hook's stdin payload (string or object).

Advisor: only configuration is compared (`advisor:` in harness.yml vs `advisorModel` in
.claude/settings.json). Claude Code does not report the live advisor to hooks, so an advisor chosen
with /advisor or --advisor for the session cannot be seen here. A harness.yml without an `advisor:`
key means the project does not manage an advisor: no check.

Never blocks: always exits 0. Output is JSON for Claude Code (systemMessage + additionalContext).
"""
import json
import os
import re
import sys


def scalar(path, key, frontmatter=False):
    """Top-level `key: value` from a simple YAML file (no external YAML dependency)."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    if frontmatter:
        if not lines or lines[0].strip() != "---":
            return ""
        end = next((i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), len(lines))
        lines = lines[1:end]
    for line in lines:
        m = re.match(r"^" + re.escape(key) + r":\s*(.*)$", line)
        if m:
            val = re.sub(r"\s+#.*$", "", m.group(1)).strip().strip("\"'")
            return val
    return ""


def norm(s):
    """Lowercase, drop context suffixes like [1m]."""
    return re.sub(r"\[[^\]]*\]", "", str(s)).strip().lower()


def actual_model(data):
    m = data.get("model")
    if isinstance(m, dict):
        m = " ".join(str(v) for v in m.values() if isinstance(v, (str, int)))
    return norm(m) if m else ""


def emit(user_msg, agent_msg=None):
    out = {"systemMessage": user_msg}
    if agent_msg:
        out["hookSpecificOutput"] = {"hookEventName": "SessionStart", "additionalContext": agent_msg}
    print(json.dumps(out))


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def model_check(root, data):
    """(user_msg, agent_msg) on a model mismatch or an unverifiable model, else None."""
    expected, source = norm(scalar(os.path.join(root, "harness.yml"), "model")), "harness.yml"

    active = os.path.join(root, "tasks", ".active")
    try:
        with open(active, encoding="utf-8") as fh:
            task = fh.read().strip()
    except OSError:
        task = ""
    if task and re.match(r"^[\w.-]+$", task):
        tdir = os.path.join(root, "tasks", task)
        contract = os.path.join(tdir, "contract.md")
        status = scalar(contract, "status", frontmatter=True)
        over = norm(scalar(contract, "model", frontmatter=True))
        if status.upper().startswith("APPROVED") and not os.path.exists(os.path.join(tdir, "receipt.md")) \
                and over and over != "default":
            expected, source = over, "tasks/%s/contract.md" % task

    if not expected or expected == "default":
        return None  # project does not pin a model: nothing to check

    actual = actual_model(data)
    if not actual:
        return ("model-check: Claude Code did not report the session model; cannot verify it is '%s' "
                "(%s). Check the status line." % (expected, source), None)
    if expected in actual:
        return None  # match: stay silent

    return (
        "MODEL MISMATCH: %s expects '%s', this session runs '%s'. Switch with /model "
        "or accept it knowingly." % (source, expected, actual),
        "MODEL MISMATCH: %s expects model '%s' but this session runs '%s'. You cannot switch the "
        "model yourself. In your first reply tell the human, and do not start or continue a task "
        "until they have switched with /model or confirmed the mismatch is fine." % (source, expected, actual),
    )


def advisor_drift(root):
    """(user_msg, agent_msg) when harness.yml and .claude/settings.json disagree on the advisor, else None."""
    want = norm(scalar(os.path.join(root, "harness.yml"), "advisor"))
    if not want:
        return None  # harness.yml does not manage an advisor
    pinned = norm(read_json(os.path.join(root, ".claude", "settings.json")).get("advisorModel") or "")
    ok = pinned in ("", "none") if want == "none" else pinned == want
    if ok:
        return None
    return (
        "ADVISOR DRIFT: harness.yml expects advisor '%s' but .claude/settings.json has advisorModel '%s'. "
        "Run ./scripts/init.sh or edit both files by hand." % (want, pinned or "none"),
        "ADVISOR DRIFT: harness.yml expects advisor '%s' but .claude/settings.json has advisorModel '%s'. "
        "You cannot edit either file. Tell the human in your first reply; the task may continue." % (want, pinned or "none"),
    )


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return  # malformed input: nothing to judge
    root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()

    parts = [r for r in (model_check(root, data), advisor_drift(root)) if r]
    if not parts:
        return
    user = "\n".join(p[0] for p in parts)
    agent = "\n".join(p[1] for p in parts if p[1])
    emit(user, agent or None)


if __name__ == "__main__":
    main()
