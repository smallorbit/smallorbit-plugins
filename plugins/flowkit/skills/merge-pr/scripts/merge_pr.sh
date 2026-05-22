#!/usr/bin/env bash
set -euo pipefail

# merge_pr.sh — rebase-merge a GitHub PR, retarget stacked children, clean blocking worktrees.
#
# Usage:
#   merge_pr.sh [<pr_number>]
#
# If <pr_number> is omitted, resolves the open PR for the current branch.
#
# Success: exit 0, one bare JSON object on stdout (jq parseable).
# Failure: non-zero exit, human-readable stderr, empty stdout.
# Invalid args: exit 2.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE_PR_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$(dirname "$MERGE_PR_DIR")"
WITH_CLEAN_SH="$SKILLS_DIR/with-clean-workspace/scripts/with_clean_workspace.sh"

usage() {
  echo "merge_pr: usage: merge_pr.sh [<pr_number>]" >&2
}

_find_worktree_for_branch() {
  git worktree list --porcelain \
    | awk -v target="refs/heads/$1" '
        /^worktree / { wt = $0; sub(/^worktree /, "", wt) }
        $0 == "branch " target { print wt }
      '
}

if [[ $# -gt 1 ]]; then
  echo "merge_pr: at most one optional PR number (got $# arguments)" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
  esac
  if [[ ! "$1" =~ ^[0-9]+$ ]]; then
    echo "merge_pr: PR number must be numeric, got: $1" >&2
    exit 2
  fi
  PR_NUM="$1"
else
  PR_NUM=""
fi

for cmd in jq git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "merge_pr: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if [[ ! -f "$WITH_CLEAN_SH" ]]; then
  echo "merge_pr: expected with-clean-workspace at $WITH_CLEAN_SH (flowkit layout)" >&2
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "merge_pr: not on a named branch (detached HEAD?) — cannot resolve PR" >&2
  exit 1
fi

if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq 'if length > 0 then .[0].number else empty end')
fi

if [[ -z "$PR_NUM" ]]; then
  echo "merge_pr: No open PR found for branch '${BRANCH}'. Run open-pr first." >&2
  exit 1
fi

PR_META=$(gh pr view "$PR_NUM" --json headRefName,baseRefName)
HEAD_BRANCH=$(printf '%s' "$PR_META" | jq -r '.headRefName')
BASE_BRANCH=$(printf '%s' "$PR_META" | jq -r '.baseRefName')

if [[ -z "$HEAD_BRANCH" || "$HEAD_BRANCH" == "null" ]]; then
  echo "merge_pr: could not read head ref for PR #$PR_NUM" >&2
  exit 1
fi
if [[ -z "$BASE_BRANCH" || "$BASE_BRANCH" == "null" ]]; then
  echo "merge_pr: could not read base ref for PR #$PR_NUM" >&2
  exit 1
fi

BLOCKING_WORKTREE=$(_find_worktree_for_branch "$HEAD_BRANCH")
if [[ -n "$BLOCKING_WORKTREE" ]]; then
  MAIN_WORKTREE=$(git worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
  [[ -z "$MAIN_WORKTREE" ]] && { echo "merge_pr: could not determine main worktree path" >&2; exit 1; }
  if [[ "$BLOCKING_WORKTREE" == "$MAIN_WORKTREE" ]]; then
    echo "merge_pr: switching main worktree to ${BASE_BRANCH} so head branch can be deleted cleanly." >&2
    if ! git -C "$MAIN_WORKTREE" checkout -q "$BASE_BRANCH"; then
      echo "merge_pr: cannot auto-checkout ${BASE_BRANCH} in main worktree (commit/stash uncommitted changes first), then re-run." >&2
      exit 1
    fi
  else
    CALLER_CWD=$(pwd -P)
    WT_REAL=$({ cd "$BLOCKING_WORKTREE" 2>/dev/null && pwd -P; } || echo "$BLOCKING_WORKTREE")
    if [[ "$CALLER_CWD" == "$WT_REAL" || "$CALLER_CWD" == "$WT_REAL"/* ]]; then
      echo "merge_pr: cannot remove the worktree it was invoked from (cwd: $CALLER_CWD)." >&2
      echo "  Exit the worktree first (cd to the main worktree, or run ExitWorktree), then re-run merge_pr." >&2
      exit 1
    fi
    printf 'Note: branch %s is held by worktree %s.\n' "$HEAD_BRANCH" "$BLOCKING_WORKTREE" >&2
    printf '  Auto-removing the worktree before merge so the local branch can be deleted cleanly.\n' >&2
    if ! git worktree remove --force "$BLOCKING_WORKTREE"; then
      echo "merge_pr: Cannot remove worktree at '${BLOCKING_WORKTREE}' that holds '${HEAD_BRANCH}'." >&2
      printf '  git worktree remove --force %q\n' "$BLOCKING_WORKTREE" >&2
      echo "Then re-run merge_pr." >&2
      exit 1
    fi
  fi
fi

gh pr list --base "$HEAD_BRANCH" --state open --json number --jq '.[].number' \
  | while read -r CHILD; do
    [[ -z "$CHILD" ]] && continue
    if gh pr edit "$CHILD" --base "$BASE_BRANCH" >/dev/null; then
      echo "Retargeted PR #$CHILD: base $HEAD_BRANCH → $BASE_BRANCH" >&2
    else
      echo "WARNING: Failed to retarget PR #$CHILD from $HEAD_BRANCH to $BASE_BRANCH. It will be auto-closed when $HEAD_BRANCH is deleted." >&2
    fi
  done

set +e
MERGE_STATUS=$(
  bash "$WITH_CLEAN_SH" -- bash -c '
    PR_NUM="$1"
    if gh pr merge "$PR_NUM" --rebase --delete-branch; then
      printf "%s\n" "ok"
      exit 0
    fi

    if PR_STATE=$(gh pr view "$PR_NUM" --json state --jq ".state" 2>/dev/null); then
      if [ "$PR_STATE" = "MERGED" ]; then
        printf "%s\n" "local-delete-failed"
        exit 0
      fi
    else
      echo "WARNING: could not query PR #$PR_NUM state after failed merge attempt." >&2
    fi

    printf "%s\n" "failed"
    exit 1
  ' _ "$PR_NUM"
)
MERGE_EXIT=$?
set -e

LOCAL_DELETE_FAILED=false
[[ "$MERGE_STATUS" == "local-delete-failed" ]] && LOCAL_DELETE_FAILED=true

if [[ "$LOCAL_DELETE_FAILED" == "true" ]]; then
  LEFTOVER=$(_find_worktree_for_branch "$HEAD_BRANCH")
  if [[ -n "$LEFTOVER" ]]; then
    echo "WARNING: Local branch \`$HEAD_BRANCH\` still held by worktree at \`$LEFTOVER\`." >&2
  else
    echo "WARNING: PR #$PR_NUM merged remotely but the local branch \`$HEAD_BRANCH\` could not be deleted." >&2
  fi
  echo "To clean up manually:" >&2
  [[ -n "$LEFTOVER" ]] && printf '  git worktree remove --force %q\n' "$LEFTOVER" >&2
  printf '  git branch -D %q\n' "$HEAD_BRANCH" >&2
fi

if [[ "$MERGE_EXIT" -ne 0 ]]; then
  exit 1
fi

DELETE_JSON=false
[[ "$LOCAL_DELETE_FAILED" == "true" ]] && DELETE_JSON=true

jq -n \
  --argjson pr_number "$PR_NUM" \
  --arg head_branch "$HEAD_BRANCH" \
  --argjson local_delete_failed "$DELETE_JSON" \
  '{pr_number: $pr_number, head_branch: $head_branch, local_delete_failed: $local_delete_failed}'
