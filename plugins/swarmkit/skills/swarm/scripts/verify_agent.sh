#!/usr/bin/env bash
set -euo pipefail

# verify_agent.sh — collapse Step 5 (handle completions) branch-push and
# PR-existence checks into one call per agent.
#
# Usage:
#   verify_agent.sh <issue-number>
#
# On success: exit 0, single JSON object on stdout with keys:
#   {issue, branch, branch_pushed, pushed_now, pr_exists, pr_url, pr_base}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

# Anchor to the main repo root. The harness can drop the operator's shell into
# an agent worktree after a swarm; bookkeeping operations must run from the
# main worktree, not whichever worktree happens to be CWD.
cd "$(git rev-parse --path-format=absolute --git-common-dir | xargs dirname)" || exit 1

if [[ $# -ne 1 ]]; then
  echo "verify_agent: exactly one argument required: <issue-number>" >&2
  exit 2
fi

ISSUE="$1"
if ! [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "verify_agent: issue number must be a positive integer (got '$ISSUE')" >&2
  exit 2
fi

for cmd in gh jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "verify_agent: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

BRANCH="worktree-agent-${ISSUE}"

branch_pushed=false
pushed_now=false

git fetch origin "$BRANCH" >/dev/null 2>&1 || true

if git rev-parse --verify "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
  branch_pushed=true
else
  if git rev-parse --verify "refs/heads/${BRANCH}" >/dev/null 2>&1; then
    if git push -u origin "${BRANCH}" >/dev/null 2>&1; then
      branch_pushed=true
      pushed_now=true
    else
      echo "verify_agent: failed to push branch '${BRANCH}' to origin" >&2
      exit 1
    fi
  fi
fi

pr_exists=false
pr_url=null
pr_base=null

if ! PR_JSON="$(gh pr list --head "$BRANCH" --json number,url,baseRefName,state 2>/dev/null)"; then
  echo "verify_agent: 'gh pr list' failed for branch '${BRANCH}'" >&2
  exit 1
fi

OPEN_PR="$(echo "$PR_JSON" | jq -r '[.[] | select(.state == "OPEN")] | first // empty')"

if [[ -n "$OPEN_PR" ]]; then
  pr_exists=true
  pr_url="\"$(echo "$OPEN_PR" | jq -r '.url')\""
  pr_base="\"$(echo "$OPEN_PR" | jq -r '.baseRefName')\""
fi

jq -n \
  --argjson issue "$ISSUE" \
  --arg branch "$BRANCH" \
  --argjson branch_pushed "$branch_pushed" \
  --argjson pushed_now "$pushed_now" \
  --argjson pr_exists "$pr_exists" \
  --argjson pr_url "$pr_url" \
  --argjson pr_base "$pr_base" \
  '{issue: $issue, branch: $branch, branch_pushed: $branch_pushed, pushed_now: $pushed_now, pr_exists: $pr_exists, pr_url: $pr_url, pr_base: $pr_base}'
