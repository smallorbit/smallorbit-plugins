#!/usr/bin/env bash
set -euo pipefail

# ship_epic.sh — promote a long-lived feature/<slug>-<N> epic to develop via
# rebase-merge, unset claude.flowkit.prBase, and fast-forward local develop.
#
# Usage:
#   ship_epic.sh [--epic <branch>]
#   ship_epic.sh --help
#
# Success: exit 0, one bare JSON object on stdout.
# Failure: non-zero exit, human-readable message on stderr, empty stdout.
# Invalid args: exit 2.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIP_EPIC_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$(dirname "$SHIP_EPIC_DIR")"
WITH_CLEAN_SH="$SKILLS_DIR/with-clean-workspace/scripts/with_clean_workspace.sh"

usage() {
  echo "ship_epic: usage: ship_epic.sh [--epic <branch>]"
}

# --- Argument parsing --------------------------------------------------------

EPIC_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --epic=*)
      EPIC_ARG="${1#--epic=}"
      shift
      ;;
    --epic)
      if [[ $# -lt 2 ]]; then
        echo "ship_epic: --epic requires a branch name" >&2
        exit 2
      fi
      EPIC_ARG="$2"
      shift 2
      ;;
    -*)
      echo "ship_epic: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      echo "ship_epic: unexpected positional argument: $1" >&2
      exit 2
      ;;
  esac
done

# --- Resolve epic branch -----------------------------------------------------

EPIC=""
if [[ -n "$EPIC_ARG" ]]; then
  EPIC="$EPIC_ARG"
else
  EPIC=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
fi

if [[ -z "$EPIC" || "$EPIC" == "develop" || "$EPIC" == "main" || "$EPIC" == "master" || "$EPIC" == "staging" ]]; then
  echo "ship_epic: No epic in flight. claude.flowkit.prBase is unset (or equals develop) and no --epic flag was passed. Run /cut-epic first, pass --epic <branch>, or check out the epic branch." >&2
  exit 1
fi

if [[ ! "$EPIC" =~ ^feature/ ]]; then
  echo "ship_epic: epic branch must start with 'feature/', got: $EPIC" >&2
  exit 2
fi

# --- Dependency check --------------------------------------------------------

for cmd in jq git gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ship_epic: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if [[ ! -f "$WITH_CLEAN_SH" ]]; then
  echo "ship_epic: expected with-clean-workspace at $WITH_CLEAN_SH (flowkit layout)" >&2
  exit 1
fi

# --- Fetch and push ----------------------------------------------------------

git fetch origin develop "$EPIC"
git push --set-upstream origin "$EPIC"

# --- Preflight ---------------------------------------------------------------

COMMIT_COUNT=$(git rev-list --count "origin/develop..origin/$EPIC")
if [[ "$COMMIT_COUNT" -eq 0 ]]; then
  echo "ship_epic: Epic branch has no commits ahead of develop; nothing to ship." >&2
  exit 1
fi

RAW_MERGE=$(git log "origin/develop..origin/$EPIC" --merges --grep='Merge.*worktree-agent' --oneline | head -1 || true)
if [[ -n "$RAW_MERGE" ]]; then
  echo "ship_epic: Epic branch contains raw worktree-agent merge commits. Run \`swarmkit:merge-stack\` first to squash them into linear history before shipping." >&2
  exit 1
fi

# --- Aggregate closes tokens -------------------------------------------------

CLOSES_TOKENS=$(
  git log "origin/develop..origin/$EPIC" --pretty=format:'%B' \
    | (grep -oiE '(closes|fixes|resolves) #[0-9]+' || true) \
    | awk '!seen[tolower($0)]++'
)

FOOTER_LINES=()
if [[ -n "$CLOSES_TOKENS" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && FOOTER_LINES+=("$line")
  done <<< "$CLOSES_TOKENS"
fi

EPIC_ISSUE=""
if [[ "$EPIC" =~ ([0-9]+)$ ]]; then
  EPIC_ISSUE="${BASH_REMATCH[1]}"
fi
if [[ -n "$EPIC_ISSUE" ]]; then
  FOOTER_LINES+=("Refs #$EPIC_ISSUE")
fi

if [[ ${#FOOTER_LINES[@]} -gt 0 ]]; then
  for line in "${FOOTER_LINES[@]}"; do
    if echo "$line" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+[[:space:]]+#[0-9]+'; then
      echo "ship_epic: PR body footer contains a space-separated closing-keyword line ('$line'). GitHub only parses one keyword per line; trailing refs would silently stay open. Rewrite with one token per line." >&2
      exit 1
    fi
  done
fi

# --- Build PR title and body -------------------------------------------------

SLUG="${EPIC#feature/}"
CHILD_COUNT=$(git log "origin/develop..origin/$EPIC" --oneline | wc -l | tr -d '[:space:]')

PR_TITLE="feat(epic): ship $SLUG"

FOOTER_TEXT=""
if [[ ${#FOOTER_LINES[@]} -gt 0 ]]; then
  FOOTER_TEXT=$(printf '%s\n' "${FOOTER_LINES[@]}")
fi

PR_BODY="## Summary

Ship epic \`$EPIC\` to develop via rebase-merge. This branch contains $CHILD_COUNT squashed child commit(s) that will replay linearly onto develop's first-parent line.

## Changes

- Rebase-merge promotes $CHILD_COUNT squashed child PR(s) onto develop linearly.
- \`claude.flowkit.prBase\` will be unset after merge; epic branch deleted.

## Test plan

- [ ] Verify \`git log --first-parent origin/develop\` shows $CHILD_COUNT new commit(s) with no merge bubbles.
- [ ] Verify \`git config --get claude.flowkit.prBase\` is empty after ship."

if [[ -n "$FOOTER_TEXT" ]]; then
  PR_BODY="$PR_BODY

$FOOTER_TEXT"
fi

# --- Open PR -----------------------------------------------------------------

PR_URL=$(gh pr create \
  --base develop \
  --head "$EPIC" \
  --title "$PR_TITLE" \
  --body "$PR_BODY")

PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
if [[ -z "$PR_NUM" ]]; then
  echo "ship_epic: could not parse PR number from URL: $PR_URL" >&2
  exit 1
fi

# --- Rebase-merge ------------------------------------------------------------

set +e
bash "$WITH_CLEAN_SH" -- gh pr merge "$PR_NUM" --rebase --delete-branch
MERGE_EXIT=$?
set -e

if [[ $MERGE_EXIT -ne 0 ]]; then
  echo "ship_epic: Rebase-merge failed (likely a conflict). Resolve with: git checkout $EPIC && git fetch origin && git rebase origin/develop, then re-run /ship-epic." >&2
  exit 1
fi

# --- Unset claude.flowkit.prBase ---------------------------------------------

PR_BASE_UNSET=false
if git config --get claude.flowkit.prBase >/dev/null 2>&1; then
  git config --unset claude.flowkit.prBase
  PR_BASE_UNSET=true
fi

# --- Fast-forward local develop ----------------------------------------------

git fetch origin develop

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
if [[ "$CURRENT_BRANCH" == "HEAD" || "$CURRENT_BRANCH" == "$EPIC" ]]; then
  git checkout develop 2>/dev/null || true
  echo "ship_epic: checked out develop (was on now-deleted epic branch)" >&2
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
fi

DEVELOP_ADVANCED=false
if [[ "$CURRENT_BRANCH" == "develop" ]]; then
  git pull --ff-only origin develop
  DEVELOP_ADVANCED=true
fi

# --- Emit JSON ---------------------------------------------------------------

if [[ ${#FOOTER_LINES[@]} -gt 0 ]]; then
  CLOSES_JSON=$(printf '%s\n' "${FOOTER_LINES[@]}" | jq -R . | jq -s .)
else
  CLOSES_JSON="[]"
fi

jq -n \
  --arg epic_branch "$EPIC" \
  --argjson pr_number "$PR_NUM" \
  --arg pr_url "$PR_URL" \
  --argjson closes_tokens "$CLOSES_JSON" \
  --argjson pr_base_unset "$PR_BASE_UNSET" \
  --argjson develop_advanced "$DEVELOP_ADVANCED" \
  '{
    epic_branch: $epic_branch,
    pr_number: $pr_number,
    pr_url: $pr_url,
    closes_tokens: $closes_tokens,
    pr_base_unset: $pr_base_unset,
    develop_advanced: $develop_advanced
  }'
