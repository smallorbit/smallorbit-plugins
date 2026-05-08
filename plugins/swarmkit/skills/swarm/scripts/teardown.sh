#!/usr/bin/env bash
set -euo pipefail

# teardown.sh — collapse the loop-mode teardown phase (base restore +
# claude.flowkit.prBase unset) into one call, mirroring preflight.sh.
#
# Usage:
#   teardown.sh [--base <branch>] [--keep-pr-base]
#
# On success: exit 0, single JSON object on stdout with keys:
#   {base, base_restored, config_unset}                       (default shape)
#   {base, base_restored, config_unset, config_kept_for_epic} (when --keep-pr-base)
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

# Anchor to the main repo root. The harness can drop the operator's shell into
# an agent worktree after a swarm; `git checkout <base>` then fails because
# `<base>` is already checked out in the main worktree.
cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" || exit 1

BASE="develop"
KEEP_PR_BASE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || { echo "teardown: --base requires a value" >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    --keep-pr-base)
      KEEP_PR_BASE=1
      shift
      ;;
    *)
      echo "teardown: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "teardown: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

config_unset=false
if [[ $KEEP_PR_BASE -eq 0 ]]; then
  if git config --local --get claude.flowkit.prBase >/dev/null 2>&1; then
    if ! git config --local --unset claude.flowkit.prBase >/dev/null 2>&1; then
      echo "teardown: failed to unset claude.flowkit.prBase" >&2
      exit 1
    fi
    config_unset=true
  fi
fi

base_restored=false
if ! git checkout "$BASE" >/dev/null 2>&1; then
  echo "teardown: 'git checkout $BASE' failed — check for uncommitted changes or a detached HEAD conflict" >&2
  exit 1
fi
if ! git pull origin "$BASE" >/dev/null 2>&1; then
  echo "teardown: 'git pull origin $BASE' failed" >&2
  exit 1
fi
base_restored=true

if [[ $KEEP_PR_BASE -eq 1 ]]; then
  jq -n \
    --arg base "$BASE" \
    --argjson base_restored "$base_restored" \
    --argjson config_unset "false" \
    --argjson config_kept_for_epic "true" \
    '{base: $base, base_restored: $base_restored, config_unset: $config_unset, config_kept_for_epic: $config_kept_for_epic}'
else
  jq -n \
    --arg base "$BASE" \
    --argjson base_restored "$base_restored" \
    --argjson config_unset "$config_unset" \
    '{base: $base, base_restored: $base_restored, config_unset: $config_unset}'
fi
