---
name: merge-pr
description: Squash-merge the open PR for the current branch and delete the remote branch.
triggers:
  - "/merge-pr"
  - "merge this PR"
  - "merge the PR"
  - "squash and merge"
allowed-tools: Bash
---

# merge-pr

Squash-merge the open PR for the current branch and delete the remote branch.

## Input

`$ARGUMENTS` — optional PR number. If omitted, the skill auto-detects the open PR for the current branch.

## Process

### 1. Determine current branch

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

### 2. Find the open PR

If `$ARGUMENTS` is provided, use it as `PR_NUM`. Otherwise:

```bash
PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number')
```

If `PR_NUM` is empty, abort with:

> No open PR found for branch `$BRANCH`. Run /open-pr first.

### 3. Resolve the PR head branch

```bash
HEAD_BRANCH=$(gh pr view "$PR_NUM" --json headRefName --jq '.headRefName')
```

### 4. Pre-clean any agent worktrees blocking the head branch

`gh pr merge --delete-branch` deletes the local branch after the remote merge. Git refuses to delete a branch that is currently checked out in a worktree, so any worktree (typically a swarmkit `.claude/worktrees/agent-N` produced by `/swarmkit:swarm-plus`) holding `HEAD_BRANCH` must be removed first.

```bash
# Returns the worktree path currently checked out on the given branch, or empty.
# Literal-string `==` compare; safely handles slashed refs (e.g. refs/heads/feat/foo-123).
_find_worktree_for_branch() {
  git worktree list --porcelain \
    | awk -v target="refs/heads/$1" '
        /^worktree / { wt = $2 }
        $0 == "branch " target { print wt }
      '
}

BLOCKING_WORKTREE=$(_find_worktree_for_branch "$HEAD_BRANCH")

if [ -n "$BLOCKING_WORKTREE" ]; then
  printf 'Note: branch %s is held by worktree %s.\n' "$HEAD_BRANCH" "$BLOCKING_WORKTREE" >&2
  printf '  Auto-removing the worktree before merge so the local branch can be deleted cleanly.\n' >&2
  git worktree remove --force "$BLOCKING_WORKTREE"
fi
```

If `git worktree remove` fails, abort with:

> Cannot remove worktree at `$BLOCKING_WORKTREE` that holds `$HEAD_BRANCH`. Remove it manually with:
>
> ```bash
> git worktree remove --force <path>
> ```
>
> Then re-run /merge-pr.

### 5. Retarget any child PRs stacked on this PR's head branch

`gh pr merge --delete-branch` deletes the head branch on the remote. GitHub auto-CLOSES (not merges) any open PRs whose `baseRefName` equals the deleted branch, silently abandoning their diffs. Pre-empt this by enumerating those child PRs and retargeting each to the merging PR's base before the squash.

```bash
BASE_BRANCH=$(gh pr view "$PR_NUM" --json baseRefName --jq '.baseRefName')

gh pr list --base "$HEAD_BRANCH" --state open --json number --jq '.[].number' \
  | while read CHILD; do
      [ -z "$CHILD" ] && continue
      if gh pr edit "$CHILD" --base "$BASE_BRANCH" >/dev/null; then
        echo "Retargeted PR #$CHILD: base $HEAD_BRANCH → $BASE_BRANCH" >&2
      else
        echo "WARNING: Failed to retarget PR #$CHILD from $HEAD_BRANCH to $BASE_BRANCH. It will be auto-closed when $HEAD_BRANCH is deleted." >&2
      fi
    done
```

### 6. Squash-merge and delete the remote branch

`gh pr merge --squash --delete-branch` triggers an implicit local `git pull` after the merge. If the workspace is dirty that pull fails with `cannot pull with rebase: You have unstaged changes`. Use the `flowkit:with-clean-workspace` script wrapper so stash behavior is consistent across callers:

```bash
WITH_CLEAN_WORKSPACE_DIR="$(dirname "$SKILL_DIR")/with-clean-workspace"
set +e
MERGE_STATUS=$(
  bash "$WITH_CLEAN_WORKSPACE_DIR/scripts/with_clean_workspace.sh" -- \
    bash -c '
      PR_NUM="$1"
      if gh pr merge "$PR_NUM" --squash --delete-branch; then
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
[ "$MERGE_STATUS" = "local-delete-failed" ] && LOCAL_DELETE_FAILED=true

if [ "$LOCAL_DELETE_FAILED" = "true" ]; then
  LEFTOVER=$(_find_worktree_for_branch "$HEAD_BRANCH")
  if [ -n "$LEFTOVER" ]; then
    echo "WARNING: Local branch \`$HEAD_BRANCH\` still held by worktree at \`$LEFTOVER\`." >&2
  else
    echo "WARNING: PR #$PR_NUM merged remotely but the local branch \`$HEAD_BRANCH\` could not be deleted." >&2
  fi
  echo "To clean up manually:" >&2
  [ -n "$LEFTOVER" ] && echo "  git worktree remove --force $LEFTOVER" >&2
  echo "  git branch -D $HEAD_BRANCH" >&2
fi

[ "$MERGE_EXIT" -ne 0 ] && exit 1
```

### 7. Report

Print a summary:

> Merged PR #N.

## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always squash-merge (never merge commit or rebase merge)
- Always delete the remote branch on merge (`--delete-branch`)
