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

# Anchor to the main repo root. The harness can drop the operator's shell into
# an agent worktree after a swarm; without this anchor `git branch
# --show-current` would report the agent's branch as caller_branch and the
# downstream `git checkout <caller_branch>` would fail.
cd "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)" || exit 1

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

# Parse porcelain output into tab-separated "path<TAB>branch" pairs, one per
# worktree stanza that has a checked-out (non-detached) branch.
# Lines with no branch line (detached HEAD) are omitted.
all_wt_pairs="$(git worktree list --porcelain | awk '
  /^worktree / { path = $2; branch = "" }
  /^branch refs\/heads\// { branch = substr($0, 19) }
  /^$/ { if (path != "" && branch != "") print path "\t" branch; path = ""; branch = "" }
  END  { if (path != "" && branch != "") print path "\t" branch }
')"

# Worktrees to remove: non-main paths whose basename matches agent-* or worktree-agent-*.
worktrees_to_remove=()
while IFS=$'\t' read -r path branch; do
  [[ "$path" == "$main_worktree" ]] && continue
  if [[ "$path" =~ worktrees/(agent-|worktree-agent-) ]]; then
    worktrees_to_remove+=("$path")
  fi
done <<< "$all_wt_pairs"

# Produce a newline-delimited list of branches checked out by worktrees NOT in
# the removal set (excluding main worktree).
other_active_branches_list=""
while IFS=$'\t' read -r path branch; do
  [[ "$path" == "$main_worktree" ]] && continue
  # Skip if this path is in the removal set.
  in_removal=false
  for rpath in "${worktrees_to_remove[@]+"${worktrees_to_remove[@]}"}"; do
    if [[ "$rpath" == "$path" ]]; then
      in_removal=true
      break
    fi
  done
  [[ "$in_removal" == true ]] && continue
  other_active_branches_list+="$branch"$'\n'
done <<< "$all_wt_pairs"

branches_to_delete=()
stuck=()
while IFS= read -r branch; do
  if [[ "$branch" == worktree-agent-* ]]; then
    if printf '%s' "$other_active_branches_list" | grep -qxF "$branch"; then
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
