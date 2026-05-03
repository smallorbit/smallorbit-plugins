#!/usr/bin/env bash
set -euo pipefail

# push_or_pr.sh — publish pending commits on the current branch by pushing
# directly when allowed, or by creating a feature branch and opening a PR
# when origin rejects the push because the target branch is protected.
#
# Usage:
#   push_or_pr.sh --prefix <name> --title <title> --body <body> [--base <branch>]
#
# Args:
#   --prefix <name>    Branch-name prefix for the auto-created feature branch
#                      when the fallback engages (e.g. "chore/bump-plugins").
#                      The script appends "-YYYY-MM-DD" and a numeric suffix
#                      on collision.
#   --title <title>    Title for the fallback PR.
#   --body <body>      Body for the fallback PR. Multi-line strings are fine
#                      (caller quotes the value).
#   --base <branch>    Base branch for the fallback PR. Default: develop.
#
# Behavior:
#   1. Compares HEAD against origin/<current-branch>. If no pending commits,
#      emits {"push_result":"noop"} and exits 0.
#   2. Otherwise attempts `git push origin HEAD:<current-branch>`.
#   3. On success, emits {"push_result":"direct", ...} and exits 0.
#   4. On failure, classifies stderr. If the message matches a branch-
#      protection rejection (GH006 / repository rule violations / protected
#      branch hook declined), engages the fallback:
#      a. Saves HEAD as $SAVED.
#      b. Picks a non-colliding feature-branch name from $PREFIX + date.
#      c. Checks out the new branch at $SAVED, then resets the original
#         branch's local ref to its upstream (so the protected branch no
#         longer holds the unpublished commit). Order matters — `git branch
#         -f` refuses to update the currently-checked-out branch.
#      d. Pushes the new branch and opens a PR via `gh pr create`.
#      e. Emits {"push_result":"pr", ...} and exits 0.
#   5. Any other push failure (auth, network, divergence) exits non-zero with
#      the captured stderr surfaced to the caller.
#
# Output (success): a single bare JSON object on stdout with keys:
#   push_result    — "direct" | "pr" | "noop"
#   branch         — current branch at invocation time
#   new_branch     — fallback feature branch (only when push_result=pr)
#   pr_url         — fallback PR URL (only when push_result=pr)
#   pending_count  — number of commits ahead of upstream at invocation
#
# Output (failure): exit non-zero, stdout empty, human-readable stderr.

PREFIX=""
PR_TITLE=""
PR_BODY=""
BASE="develop"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "push_or_pr: --prefix requires a value" >&2; exit 2; }
      PREFIX="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || { echo "push_or_pr: --title requires a value" >&2; exit 2; }
      PR_TITLE="$2"
      shift 2
      ;;
    --body)
      [[ $# -ge 2 ]] || { echo "push_or_pr: --body requires a value" >&2; exit 2; }
      PR_BODY="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || { echo "push_or_pr: --base requires a value" >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    *)
      echo "push_or_pr: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in jq git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "push_or_pr: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
  echo "push_or_pr: not on a branch (detached HEAD?) — refusing to publish" >&2
  exit 1
fi

UPSTREAM_REF="origin/$BRANCH"
if ! git rev-parse --verify --quiet "$UPSTREAM_REF" >/dev/null; then
  echo "push_or_pr: $UPSTREAM_REF does not exist locally — run 'git fetch origin' before invoking" >&2
  exit 1
fi

PENDING=$(git rev-list --count "$UPSTREAM_REF..HEAD")

if [[ "$PENDING" -eq 0 ]]; then
  jq -n \
    --arg push_result "noop" \
    --arg branch "$BRANCH" \
    --argjson pending_count 0 \
    '{push_result: $push_result, branch: $branch, pending_count: $pending_count}'
  exit 0
fi

PUSH_LOG=$(mktemp)
trap 'rm -f "$PUSH_LOG"' EXIT

if git push origin "HEAD:$BRANCH" >"$PUSH_LOG" 2>&1; then
  jq -n \
    --arg push_result "direct" \
    --arg branch "$BRANCH" \
    --argjson pending_count "$PENDING" \
    '{push_result: $push_result, branch: $branch, pending_count: $pending_count}'
  exit 0
fi

PUSH_OUTPUT=$(cat "$PUSH_LOG")
if ! printf '%s' "$PUSH_OUTPUT" | grep -qiE "(protected branch|GH006|push declined due to repository rule|protected branch hook declined)"; then
  echo "push_or_pr: push to $BRANCH failed for a reason other than branch protection:" >&2
  printf '%s\n' "$PUSH_OUTPUT" >&2
  exit 1
fi

if [[ -z "$PREFIX" || -z "$PR_TITLE" || -z "$PR_BODY" ]]; then
  echo "push_or_pr: branch protection rejected the push, but --prefix / --title / --body are required to engage the fallback" >&2
  exit 2
fi

echo "push_or_pr: direct push to $BRANCH rejected by branch protection — falling back to feature branch + PR." >&2

SAVED=$(git rev-parse HEAD)
DATE=$(date +%Y-%m-%d)
NEW_BRANCH="${PREFIX}-${DATE}"
N=1
while git ls-remote --exit-code origin "refs/heads/$NEW_BRANCH" >/dev/null 2>&1 \
   || git rev-parse --verify --quiet "refs/heads/$NEW_BRANCH" >/dev/null; do
  N=$((N + 1))
  NEW_BRANCH="${PREFIX}-${DATE}-${N}"
done

git checkout -b "$NEW_BRANCH" "$SAVED" >/dev/null 2>&1
git branch -f "$BRANCH" "$UPSTREAM_REF" >/dev/null 2>&1

if ! git push -u origin "$NEW_BRANCH" >/dev/null 2>&1; then
  echo "push_or_pr: failed to push fallback branch '$NEW_BRANCH'" >&2
  exit 1
fi

PR_URL=$(gh pr create \
  --base "$BASE" \
  --head "$NEW_BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY")

if [[ -z "$PR_URL" ]]; then
  echo "push_or_pr: 'gh pr create' returned empty URL" >&2
  exit 1
fi

jq -n \
  --arg push_result "pr" \
  --arg branch "$BRANCH" \
  --arg new_branch "$NEW_BRANCH" \
  --arg pr_url "$PR_URL" \
  --argjson pending_count "$PENDING" \
  '{push_result: $push_result, branch: $branch, new_branch: $new_branch, pr_url: $pr_url, pending_count: $pending_count}'
