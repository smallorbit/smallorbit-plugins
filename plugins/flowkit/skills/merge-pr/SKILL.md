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
_find_worktree_for_branch() {
  git worktree list --porcelain \
    | awk -v target="refs/heads/$1" '
        /^worktree / { wt = $2 }
        $0 == "branch " target { print wt }
      '
}

BLOCKING_WORKTREE=$(_find_worktree_for_branch "$HEAD_BRANCH")

if [ -n "$BLOCKING_WORKTREE" ]; then
  git worktree remove --force "$BLOCKING_WORKTREE"
fi
```

If `git worktree remove` fails, abort with:

> Cannot remove worktree at `$BLOCKING_WORKTREE` that holds `$HEAD_BRANCH`. Remove it manually with:
>
> ```
> git worktree remove --force <path>
> ```
>
> Then re-run /merge-pr.

### 5. Squash-merge and delete the remote branch

`gh pr merge --squash --delete-branch` triggers an implicit local `git pull` after the merge. If the workspace is dirty that pull fails with `cannot pull with rebase: You have unstaged changes`. The block below mirrors the stash-guard logic from `flowkit:with-clean-workspace` — auto-stashing dirty state before the merge and restoring it after:

```bash
DIRTY=false
if [ -n "$(git status --porcelain)" ]; then
  DIRTY=true
  git stash push -u -m "flowkit-auto-stash" >/dev/null
fi

if gh pr merge "$PR_NUM" --squash --delete-branch; then
  MERGE_OK=true
  LOCAL_DELETE_FAILED=false
else
  # gh pr merge exited non-zero — re-query the PR state. If the remote merge
  # actually succeeded, only the local branch-delete failed (e.g. another
  # worktree still held the branch, or a race condition). Treat that as a
  # recoverable warning, not a hard failure.
  PR_STATE=$(gh pr view "$PR_NUM" --json state --jq '.state' 2>/dev/null)
  if [ "$PR_STATE" = "MERGED" ]; then
    MERGE_OK=true
    LOCAL_DELETE_FAILED=true
  else
    MERGE_OK=false
    LOCAL_DELETE_FAILED=false
  fi
fi

if [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "true" ]; then
  if ! git stash pop; then
    echo "WARNING: stash pop conflicted. Your changes are preserved on the stash stack." >&2
    echo "Run \`git stash list\` to see the saved entry (message: flowkit-auto-stash) and \`git stash pop\` after resolving." >&2
  fi
elif [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "false" ]; then
  echo "WARNING: merge failed — stash preserved. Run \`git stash pop\` after resolving the merge error." >&2
fi

if [ "$LOCAL_DELETE_FAILED" = "true" ]; then
  echo "WARNING: PR #$PR_NUM merged remotely but the local branch \`$HEAD_BRANCH\` could not be deleted." >&2
  echo "To clean up manually:" >&2
  LEFTOVER=$(_find_worktree_for_branch "$HEAD_BRANCH")
  [ -n "$LEFTOVER" ] && echo "  git worktree remove --force $LEFTOVER" >&2
  echo "  git branch -D $HEAD_BRANCH" >&2
fi

[ "$MERGE_OK" = "false" ] && exit 1
```

### 6. Report

Print a summary:

> Merged PR #N.


## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always squash-merge (never merge commit or rebase merge)
- Always delete the remote branch on merge (`--delete-branch`)
