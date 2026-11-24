#!/usr/bin/env bash
# One-time project setup: asks a few questions and fills harness.yml + CLAUDE.md.
# Run it yourself (the agent cannot edit harness.yml). Safe to re-run: it rewrites the commands block.
set -eu
cd "$(dirname "$0")/.."

ask() { # ask "Question" "default" -> echoes answer
  local reply
  read -r -p "$1${2:+ [$2]}: " reply
  echo "${reply:-$2}"
}

NAME=$(ask "Project name" "$(basename "$PWD")")
echo "Available profiles: $(ls profiles | grep -v '\.md$' | tr '\n' ' ')"
PROFILE=$(ask "Profile" "generic" | tr '[:upper:]' '[:lower:]')
[ -f "profiles/$PROFILE/commands.yml" ] || { echo "Profile '$PROFILE' not found (profiles/$PROFILE/commands.yml)" >&2; exit 1; }

# Model for this project. Pinned into .claude/settings.json so that `/model` in another
# project (which writes a user-level default) does not change this one.
CUR_MODEL=$(awk '/^model:/ { v = $2; sub(/#.*/, "", v); gsub(/"/, "", v); print v; exit }' harness.yml)
echo "Model: sonnet for routine work, opus for hard architecture work (aliases or a full model id)"
MODEL=$(ask "Model for this project" "${CUR_MODEL:-sonnet}" | tr '[:upper:]' '[:lower:]')
printf '%s' "$MODEL" | grep -Eq '^[a-z0-9._-]+(\[[0-9a-z]+\])?$' || { echo "Invalid model value: '$MODEL'" >&2; exit 1; }

# Advisor: a stronger model the session model consults at decision points. Pinned into
# .claude/settings.json ("advisorModel") for the same reason as the model. `none` = pin nothing.
CUR_ADVISOR=$(awk '/^advisor:/ { v = $2; sub(/#.*/, "", v); gsub(/"/, "", v); print v; exit }' harness.yml)
echo "Advisor: none, or a model at or above the project model (opus | fable, or a full model id)"
ADVISOR=$(ask "Advisor for this project" "${CUR_ADVISOR:-none}" | tr '[:upper:]' '[:lower:]')
printf '%s' "$ADVISOR" | grep -Eq '^(none|[a-z0-9._-]+(\[[0-9a-z]+\])?)$' || { echo "Invalid advisor value: '$ADVISOR'" >&2; exit 1; }
rank() { # 0 = unknown model id (not compared)
  case "$1" in
    *haiku*) echo 1 ;; *sonnet*) echo 2 ;; *opus*) echo 3 ;; *fable*|*mythos*) echo 4 ;; *) echo 0 ;;
  esac
}
if [ "$ADVISOR" != "none" ]; then
  MR=$(rank "$MODEL"); AR=$(rank "$ADVISOR")
  if [ "$MR" -gt 0 ] && [ "$AR" -gt 0 ] && [ "$AR" -lt "$MR" ]; then
    echo "The advisor must rank at or above the project model ('$ADVISOR' is below '$MODEL')." >&2; exit 1
  fi
  if [ "$MR" -eq 0 ] || [ "$AR" -eq 0 ]; then echo "Note: could not compare '$MODEL' and '$ADVISOR'; check the pair yourself."; fi
fi

frag=$(cat "profiles/$PROFILE/commands.yml")

if [ "$PROFILE" = "ios" ]; then
  SCHEME=$(ask "Xcode scheme" "")
  CONTAINER=$(ask "Xcode container flag (e.g. -workspace App.xcworkspace or -project App.xcodeproj)" "")
  DEST=$(ask "Test destination" "platform=iOS Simulator,name=iPhone 16")
  UNIT=$(ask "Unit test target" "${SCHEME}Tests")
  UITGT=$(ask "UI test target" "${SCHEME}UITests")
  frag=${frag//__SCHEME__/$SCHEME}
  frag=${frag//__CONTAINER__/$CONTAINER}
  frag=${frag//__DESTINATION__/$DEST}
  frag=${frag//__UNIT_TARGET__/$UNIT}
  frag=${frag//__UI_TARGET__/$UITGT}
fi

VAULT=$(ask "Obsidian vault absolute path for receipts (empty = none)" "")

tmp=$(mktemp)
fragfile=$(mktemp)
printf '%s\n' "$frag" > "$fragfile"

# 1) replace the commands block between the markers
awk -v fragfile="$fragfile" '
  /# BEGIN commands/ { print; while ((getline l < fragfile) > 0) print l; skip = 1; next }
  /# END commands/   { skip = 0 }
  !skip { print }
' harness.yml > "$tmp"

# 2) name, profile, model, advisor, vault
awk -v name="$NAME" -v profile="$PROFILE" -v model="$MODEL" -v advisor="$ADVISOR" -v vault="$VAULT" '
  /^name:/            { print "name: \"" name "\""; next }
  /^profile:/         { print "profile: " profile; next }
  /^model:/           { print "model: " model; next }
  /^advisor:/         { print "advisor: " advisor; next }
  /^obsidian_vault:/  { print "obsidian_vault: \"" vault "\""; next }
  { print }
' "$tmp" > harness.yml
rm -f "$tmp" "$fragfile"

# 2b) pin the model and the advisor in the project settings (project scope beats the user-level default)
python3 - "$MODEL" "$ADVISOR" <<'PY'
import json, sys
p = ".claude/settings.json"
d = json.load(open(p, encoding="utf-8"))
model, advisor = sys.argv[1], sys.argv[2]
rest = {k: v for k, v in d.items() if k not in ("model", "advisorModel")}
out = {"model": model}
if advisor != "none":
    out["advisorModel"] = advisor
out.update(rest)
with open(p, "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

# 3) CLAUDE.md title
tmp=$(mktemp)
awk -v name="$NAME" '{ sub(/__PROJECT__/, name); print }' CLAUDE.md > "$tmp" && mv "$tmp" CLAUDE.md

chmod +x scripts/*.sh .claude/hooks/guard.py .claude/hooks/model-check.py profiles/*/*.sh 2>/dev/null || true

# 4) Optional baseline commit. Without any commit, `git diff HEAD` does not work and the
#    first task has nothing to be compared against. Only for a git repo with no commits.
if git rev-parse --git-dir >/dev/null 2>&1 && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo
  ANS=$(ask "No commits yet. Make a baseline commit of the harness files (recommended)? (y/n)" "y" | tr '[:upper:]' '[:lower:]')
  if [ "$ANS" = "y" ] || [ "$ANS" = "yes" ]; then
    if [ -n "$(git config user.name || true)" ] && [ -n "$(git config user.email || true)" ]; then
      if git add -A && git commit -q -m "Harness baseline"; then
        echo "Baseline commit created."
      else
        echo "Baseline commit failed. Fix the git problem, then run: git add -A && git commit -m \"Harness baseline\"" >&2
      fi
    else
      echo "git user.name / user.email are not set, so no commit was made."
      echo "Set them, then run: git add -A && git commit -m \"Harness baseline\""
    fi
  fi
fi

echo
echo "Done. Model pinned to '$MODEL', advisor '$ADVISOR' (harness.yml + .claude/settings.json)."
if [ "$ADVISOR" = "none" ]; then echo "Note: advisor 'none' pins nothing. An advisor set globally with /advisor can still apply."; fi
echo "Review harness.yml, then fill in docs/architecture.md."
echo "Next: run ./scripts/check.sh to see which steps are configured."
