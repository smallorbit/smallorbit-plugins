#!/usr/bin/env bash
set -euo pipefail

# gather.sh — enumerate worktrees and orphaned local branches slated for cleanup.
#
# Usage:
#   gather.sh
#
# On success: exit 0, single JSON object on stdout with keys:
#   {caller_branch, main_worktree, worktrees_to_remove: [{path}], branches_to_delete: [string], stuck: [{path, branch}]}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "gather: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

caller_branch="$(git branch --show-current 2>/dev/null || true)"

main_worktree="$(git worktree list --porcelain | grep '^worktree' | head -1 | awk '{print $2}')"
if [[ -z "$main_worktree" ]]; then
  echo "gather: could not determine main worktree path" >&2
  exit 1
fi

worktrees_to_remove=()
while IFS= read -r line; do
  path="${line#worktree }"
  if [[ "$path" != "$main_worktree" ]]; then
    worktrees_to_remove+=("$path")
  fi
done < <(git worktree list --porcelain | grep '^worktree ')

active_worktree_branches=()
while IFS= read -r line; do
  branch="${line#branch refs/heads/}"
  if [[ "$line" == branch\ * ]]; then
    active_worktree_branches+=("$branch")
  fi
done < <(git worktree list --porcelain)

branches_to_delete=()
stuck=()
while IFS= read -r branch; do
  if [[ "$branch" == worktree-agent-* ]]; then
    is_active=false
    for active in "${active_worktree_branches[@]+"${active_worktree_branches[@]}"}"; do
      if [[ "$active" == "$branch" ]]; then
        is_active=true
        break
      fi
    done

    if [[ "$is_active" == true ]]; then
      stuck+=("$branch")
    else
      branches_to_delete+=("$branch")
    fi
  fi
done < <(git branch --format='%(refname:short)')

if [[ ${#worktrees_to_remove[@]} -gt 0 ]]; then
  worktrees_json="$(printf '%s\n' "${worktrees_to_remove[@]}" | jq -R '{"path": .}' | jq -s '.')"
else
  worktrees_json="[]"
fi

if [[ ${#branches_to_delete[@]} -gt 0 ]]; then
  branches_json="$(printf '%s\n' "${branches_to_delete[@]}" | jq -R '.' | jq -s '.')"
else
  branches_json="[]"
fi

if [[ ${#stuck[@]} -gt 0 ]]; then
  stuck_json="$(printf '%s\n' "${stuck[@]}" | jq -R '{"branch": .}' | jq -s '.')"
else
  stuck_json="[]"
fi

jq -n \
  --arg caller_branch "$caller_branch" \
  --arg main_worktree "$main_worktree" \
  --argjson worktrees_to_remove "$worktrees_json" \
  --argjson branches_to_delete "$branches_json" \
  --argjson stuck "$stuck_json" \
  '{caller_branch: $caller_branch, main_worktree: $main_worktree, worktrees_to_remove: $worktrees_to_remove, branches_to_delete: $branches_to_delete, stuck: $stuck}'
