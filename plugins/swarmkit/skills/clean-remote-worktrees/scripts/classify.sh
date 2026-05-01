#!/usr/bin/env bash
set -euo pipefail

# classify.sh — fetch and classify remote worktree-agent-* branches by PR state.
#
# Usage:
#   classify.sh
#
# Fetches origin, lists remote worktree-agent-* branches, queries each branch's
# most-recent PR state via `gh pr list`, and buckets them by state.
#
# On success: exit 0, single JSON object on stdout with keys:
#   {candidates: [{branch, pr_number, pr_title, state}], merged: [string],
#    closed: [string], open: [string], no_pr: [string]}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

for cmd in git gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "classify: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if ! gh auth status >/dev/null 2>&1; then
  echo "classify: gh is not authenticated — run 'gh auth login' first" >&2
  exit 1
fi

if ! git fetch origin --prune >/dev/null 2>&1; then
  echo "classify: 'git fetch origin --prune' failed" >&2
  exit 1
fi

candidates_raw="$(git ls-remote --heads origin 'worktree-agent-*' 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||')"

if [[ -z "$candidates_raw" ]]; then
  jq -n '{candidates: [], merged: [], closed: [], open: [], no_pr: []}'
  exit 0
fi

candidates_json="[]"
merged=()
closed_list=()
open_list=()
no_pr=()

while IFS= read -r branch; do
  [[ -z "$branch" ]] && continue

  pr_json="$(gh pr list --state all --head "$branch" --json number,state,title --limit 1 2>/dev/null || echo '[]')"

  pr_count="$(printf '%s' "$pr_json" | jq 'length')"

  if [[ "$pr_count" -eq 0 ]]; then
    entry="$(jq -n --arg branch "$branch" '{"branch": $branch, "pr_number": null, "pr_title": null, "state": "NO_PR"}')"
    no_pr+=("$branch")
  else
    pr_number="$(printf '%s' "$pr_json" | jq -r '.[0].number')"
    pr_title="$(printf '%s' "$pr_json" | jq -r '.[0].title')"
    pr_state="$(printf '%s' "$pr_json" | jq -r '.[0].state')"
    entry="$(jq -n --arg branch "$branch" --argjson pr_number "$pr_number" --arg pr_title "$pr_title" --arg state "$pr_state" \
      '{"branch": $branch, "pr_number": $pr_number, "pr_title": $pr_title, "state": $state}')"

    case "$pr_state" in
      MERGED) merged+=("$branch") ;;
      CLOSED) closed_list+=("$branch") ;;
      OPEN)   open_list+=("$branch") ;;
      *)      no_pr+=("$branch") ;;
    esac
  fi

  candidates_json="$(printf '%s' "$candidates_json" | jq --argjson entry "$entry" '. + [$entry]')"
done < <(printf '%s\n' "$candidates_raw")

_to_json_array() {
  local -a arr=("$@")
  if [[ ${#arr[@]} -eq 0 ]]; then
    echo '[]'
  else
    printf '%s\n' "${arr[@]}" | jq -R '.' | jq -s '.'
  fi
}
merged_json="$(_to_json_array "${merged[@]+"${merged[@]}"}")"
closed_json="$(_to_json_array "${closed_list[@]+"${closed_list[@]}"}")"
open_json="$(_to_json_array "${open_list[@]+"${open_list[@]}"}")"
no_pr_json="$(_to_json_array "${no_pr[@]+"${no_pr[@]}"}")"

jq -n \
  --argjson candidates "$candidates_json" \
  --argjson merged "$merged_json" \
  --argjson closed "$closed_json" \
  --argjson open "$open_json" \
  --argjson no_pr "$no_pr_json" \
  '{candidates: $candidates, merged: $merged, closed: $closed, open: $open, no_pr: $no_pr}'
