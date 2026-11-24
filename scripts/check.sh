#!/usr/bin/env bash
# Verification ladder: lint -> build -> unit -> arch -> (ui with --full).
# Usage: scripts/check.sh [--full] [--only STEP]
# Commands come from the `commands:` block in harness.yml.
# Exit 0: no step failed (SKIPs are listed and are NOT passes). Exit 1: a step failed.
# A command that exits with code 3 counts as "not configured" (SKIP).
set -u
cd "$(dirname "$0")/.." || exit 1
CFG="harness.yml"
FULL=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --full) FULL=1 ;;
    --only) ONLY="${2:-}"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

[ -f "$CFG" ] || { echo "harness.yml not found" >&2; exit 1; }

get_cmd() {
  awk -v k="$1" '
    /^commands:/ { f = 1; next }
    /^[^ \t#]/   { f = 0 }
    f {
      line = $0; sub(/^[ \t]+/, "", line)
      if (index(line, k ":") == 1) {
        v = substr(line, length(k) + 2)
        sub(/^[ \t]+/, "", v); sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
        if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
        print v; exit
      }
    }' "$CFG"
}

LOG=""
if [ -f tasks/.active ]; then
  t=$(tr -d '[:space:]' < tasks/.active)
  [ -n "$t" ] && [ -d "tasks/$t" ] && LOG="tasks/$t/checks.log"
fi
# A finished task (receipt exists) keeps its log as it was: a later run is not this task's evidence.
if [ -n "$LOG" ] && [ -f "tasks/$t/receipt.md" ]; then
  echo "NOTE: the active task $t is finished (receipt exists): this run is not written to its checks.log."
  LOG=""
fi
# Append a run section; never overwrite what is in the log (manual sections included).
# First line of a run: "# check run <UTC> full=<n>" (kept as it was), then head= and work= (tree fingerprint, taken now).
if [ -n "$LOG" ]; then
  if [ -s "$LOG" ]; then
    [ -n "$(tail -c1 "$LOG")" ] && printf '\n' >> "$LOG"
    printf '\n' >> "$LOG"
  fi
  head_rev=none
  work=n/a
  if git rev-parse --git-dir >/dev/null 2>&1; then
    head_rev=$(git rev-parse --short HEAD 2>/dev/null || echo none)
    if command -v shasum >/dev/null 2>&1; then
      work=$(git ls-files -z -co --exclude-standard -- . ':!tasks' 2>/dev/null | xargs -0 shasum 2>/dev/null | shasum | cut -c1-12)
    fi
  fi
  printf '# check run %s full=%s head=%s work=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FULL" "$head_rev" "$work" >> "$LOG"
fi

logline() { [ -n "$LOG" ] && printf '%s\n' "$1" >> "$LOG"; return 0; }

failed=0
halt=0
summary=""
skipped=""

for step in lint build unit arch ui; do
  if [ -n "$ONLY" ] && [ "$ONLY" != "$step" ]; then continue; fi
  cmd=$(get_cmd "$step")

  if [ "$halt" -eq 1 ]; then
    status="NOT RUN (earlier step failed)"
  elif [ "$step" = "ui" ] && [ "$FULL" -eq 0 ] && [ "$ONLY" != "ui" ]; then
    status="SKIP (quick mode, use --full)"
  elif [ -z "$cmd" ]; then
    status="SKIP (not configured)"
  else
    out=$(mktemp)
    echo ">> $step: $cmd"
    if bash -c "$cmd" >"$out" 2>&1; then
      status="PASS"
    else
      rc=$?
      if [ "$rc" -eq 3 ]; then
        status="SKIP (not configured)"
      else
        status="FAIL (exit $rc)"
        failed=1
        halt=1
        echo "---- last 30 lines of $step ----"
        tail -n 30 "$out"
        echo "--------------------------------"
      fi
    fi
    logline "## $step: $status"
    logline "command: $cmd"
    tail -n 60 "$out" >> "${LOG:-/dev/null}" 2>/dev/null
    rm -f "$out"
  fi

  case "$status" in
    SKIP*|"NOT RUN"*) skipped="$skipped $step" ; [ -z "$cmd" ] && logline "## $step: $status" ;;
  esac
  summary="$summary$(printf '%-6s %s\n' "$step" "$status")"$'\n'
done

echo
echo "=== check summary ==="
printf '%s' "$summary"
logline ""
logline "=== summary ==="
logline "$summary"
if [ -n "$skipped" ]; then
  echo "NOT VERIFIED (skipped or not run):$skipped"
  logline "NOT VERIFIED:$skipped"
fi
[ -n "$LOG" ] && echo "log: $LOG"

if [ "$failed" -eq 1 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: no failures (SKIPs are not passes)"
exit 0
