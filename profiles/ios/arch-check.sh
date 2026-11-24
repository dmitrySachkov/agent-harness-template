#!/usr/bin/env bash
# Lightweight architecture check for Swift projects: forbidden patterns per directory.
# Rules live in profiles/ios/layers.rules, one per line:
#     <directory> :: <extended regex> :: <message>
# Exit 0: all rules hold. Exit 1: violations. Exit 3: no active rules (reported as SKIP, not PASS).
set -u
cd "$(dirname "$0")/../.." || exit 1
RULES="profiles/ios/layers.rules"
[ -f "$RULES" ] || { echo "arch-check: $RULES not found"; exit 3; }

active=0
violations=0

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  dir=${line%% :: *}
  rest=${line#* :: }
  regex=${rest%% :: *}
  msg=${rest#* :: }
  [ "$msg" = "$rest" ] && msg="forbidden pattern"
  if [ ! -d "$dir" ]; then
    echo "arch-check: directory not found, rule ignored: $dir"
    continue
  fi
  active=$((active + 1))
  hits=$(grep -rnE --include='*.swift' -e "$regex" "$dir" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "VIOLATION [$dir]: $msg"
    echo "$hits" | head -n 20
    violations=$((violations + 1))
  fi
done < "$RULES"

if [ "$active" -eq 0 ]; then
  echo "arch-check: no active rules in $RULES"
  exit 3
fi
if [ "$violations" -gt 0 ]; then
  echo "arch-check: $violations rule(s) violated"
  exit 1
fi
echo "arch-check: $active rule(s) hold"
exit 0
