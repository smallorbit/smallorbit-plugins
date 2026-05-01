#!/usr/bin/env bash
set -euo pipefail

# remove.sh — perform worktree removal, prune, and orphaned branch deletion.
#
# Usage:
#   remove.sh --main-worktree <path> --caller-branch <branch> \
#             --worktrees <json-array-of-paths> --branches <json-array>
#
# All arguments are required. Pass empty JSON arrays ([]) when there is nothing
# to remove in that category.
#
# On success: exit 0, single JSON object on stdout with keys:
#   {removed: [string], remove_errors: [{path, error}], pruned_branches: [string],
#    branch_errors: [{branch, error}], caller_branch_restored: bool}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "remove: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

MAIN_WORKTREE=""
CALLER_BRANCH=""
WORKTREES_JSON="[]"
BRANCHES_JSON="[]"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-worktree)
      [[ $# -ge 2 ]] || { echo "remove: --main-worktree requires a value" >&2; exit 2; }
      MAIN_WORKTREE="$2"; shift 2 ;;
    --caller-branch)
      [[ $# -ge 2 ]] || { echo "remove: --caller-branch requires a value" >&2; exit 2; }
      CALLER_BRANCH="$2"; shift 2 ;;
    --worktrees)
      [[ $# -ge 2 ]] || { echo "remove: --worktrees requires a value" >&2; exit 2; }
      WORKTREES_JSON="$2"; shift 2 ;;
    --branches)
      [[ $# -ge 2 ]] || { echo "remove: --branches requires a value" >&2; exit 2; }
      BRANCHES_JSON="$2"; shift 2 ;;
    *)
      echo "remove: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$MAIN_WORKTREE" ]] || { echo "remove: --main-worktree is required" >&2; exit 2; }

T_WT_ERR=$(mktemp)
T_BR_ERR=$(mktemp)
trap "rm -f $T_WT_ERR $T_BR_ERR" EXIT

git worktree prune >/dev/null 2>&1 || true

cd "$MAIN_WORKTREE"

removed=()
remove_errors_parts=()

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if git worktree remove "$path" -f -f 2>"$T_WT_ERR"; then
    removed+=("$path")
  else
    err="$(cat "$T_WT_ERR")"
    remove_errors_parts+=("$(jq -n --arg path "$path" --arg error "$err" '{"path": $path, "error": $error}')")
  fi
done < <(printf '%s\n' "$WORKTREES_JSON" | jq -r '.[] | .path')

git worktree prune >/dev/null 2>&1 || true

pruned_branches=()
branch_errors_parts=()

while IFS= read -r branch; do
  [[ -z "$branch" ]] && continue
  if git branch -D "$branch" 2>"$T_BR_ERR"; then
    pruned_branches+=("$branch")
  else
    err="$(cat "$T_BR_ERR")"
    branch_errors_parts+=("$(jq -n --arg branch "$branch" --arg error "$err" '{"branch": $branch, "error": $error}')")
  fi
done < <(printf '%s\n' "$BRANCHES_JSON" | jq -r '.[]')

caller_branch_restored=false
if [[ -n "$CALLER_BRANCH" ]]; then
  if git branch --list "$CALLER_BRANCH" | grep -q .; then
    if git checkout "$CALLER_BRANCH" >/dev/null 2>&1; then
      caller_branch_restored=true
    fi
  fi
fi

if [[ ${#removed[@]} -gt 0 ]]; then
  removed_json="$(printf '%s\n' "${removed[@]}" | jq -R '.' | jq -s '.')"
else
  removed_json="[]"
fi

if [[ ${#pruned_branches[@]} -gt 0 ]]; then
  pruned_json="$(printf '%s\n' "${pruned_branches[@]}" | jq -R '.' | jq -s '.')"
else
  pruned_json="[]"
fi

if [[ ${#remove_errors_parts[@]} -gt 0 ]]; then
  remove_errors_json="$(printf '%s\n' "${remove_errors_parts[@]}" | jq -s '.')"
else
  remove_errors_json="[]"
fi

if [[ ${#branch_errors_parts[@]} -gt 0 ]]; then
  branch_errors_json="$(printf '%s\n' "${branch_errors_parts[@]}" | jq -s '.')"
else
  branch_errors_json="[]"
fi

jq -n \
  --argjson removed "$removed_json" \
  --argjson remove_errors "$remove_errors_json" \
  --argjson pruned_branches "$pruned_json" \
  --argjson branch_errors "$branch_errors_json" \
  --argjson caller_branch_restored "$caller_branch_restored" \
  '{removed: $removed, remove_errors: $remove_errors, pruned_branches: $pruned_branches, branch_errors: $branch_errors, caller_branch_restored: $caller_branch_restored}'
