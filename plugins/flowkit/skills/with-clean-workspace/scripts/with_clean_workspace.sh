#!/usr/bin/env bash
set -euo pipefail

# with_clean_workspace.sh — run a command behind flowkit's auto-stash guard.
#
# Usage:
#   with_clean_workspace.sh -- <command> [args...]
#
# Behavior:
# - If workspace is dirty, stash tracked + untracked changes.
# - Execute wrapped command exactly as passed.
# - On success: attempt stash pop. If pop conflicts, keep stash and warn.
# - On failure: keep stash and warn.
# - Exit with the wrapped command's exit code.

if [[ $# -lt 2 || "$1" != "--" ]]; then
  echo "with_clean_workspace: usage: with_clean_workspace.sh -- <command> [args...]" >&2
  exit 2
fi

shift

if ! command -v git >/dev/null 2>&1; then
  echo "with_clean_workspace: required dependency 'git' not found on PATH" >&2
  exit 1
fi

DIRTY=false
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  DIRTY=true
  git stash push -u -m "flowkit-auto-stash" >/dev/null
fi

set +e
"$@"
COMMAND_EXIT=$?
set -e

if [[ "$DIRTY" == "true" && "$COMMAND_EXIT" -eq 0 ]]; then
  if ! git stash pop; then
    echo "WARNING: stash pop conflicted. Your changes are preserved on the stash stack." >&2
    echo "Run \`git stash list\` to see the saved entry (message: flowkit-auto-stash) and \`git stash pop\` after resolving." >&2
  fi
elif [[ "$DIRTY" == "true" && "$COMMAND_EXIT" -ne 0 ]]; then
  echo "WARNING: wrapped command failed — stash preserved. Run \`git stash pop\` after resolving the command error." >&2
fi

exit "$COMMAND_EXIT"
