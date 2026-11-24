#!/usr/bin/env bash
# Copy a task receipt into the Obsidian vault set in harness.yml (obsidian_vault).
# Usage: scripts/sync-obsidian.sh [task-dir-name]   (default: the one in tasks/.active)
# One-way only: the repo is the source of truth, the vault is a reading copy.
set -eu
cd "$(dirname "$0")/.."

vault=$(awk '/^obsidian_vault:/ { v = $0; sub(/^obsidian_vault:[ \t]*/, "", v); gsub(/"/, "", v); sub(/[ \t]+#.*$/, "", v); print v; exit }' harness.yml)
name=$(awk '/^name:/ { v = $0; sub(/^name:[ \t]*/, "", v); gsub(/"/, "", v); print v; exit }' harness.yml)

if [ -z "$vault" ]; then echo "obsidian_vault is not set in harness.yml; nothing to do."; exit 0; fi
[ -d "$vault" ] || { echo "vault directory not found: $vault" >&2; exit 1; }

task="${1:-}"
[ -z "$task" ] && [ -f tasks/.active ] && task=$(tr -d '[:space:]' < tasks/.active)
[ -n "$task" ] || { echo "no task given and tasks/.active is empty" >&2; exit 1; }
src="tasks/$task/receipt.md"
[ -f "$src" ] || { echo "receipt not found: $src" >&2; exit 1; }

dest_dir="$vault/agent-runs/$name"
mkdir -p "$dest_dir"
cp "$src" "$dest_dir/$task.md"
echo "copied to $dest_dir/$task.md"
