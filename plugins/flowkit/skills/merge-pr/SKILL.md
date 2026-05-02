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

### 3. Squash-merge and delete the remote branch

`gh pr merge --squash --delete-branch` triggers an implicit local `git pull` after the merge. If the workspace is dirty that pull fails with `cannot pull with rebase: You have unstaged changes`. Wrap the call with the `flowkit:with-clean-workspace` sub-skill so any dirty state is auto-stashed and restored:

```bash
DIRTY=false
if [ -n "$(git status --porcelain)" ]; then
  DIRTY=true
  git stash push -u -m "flowkit-auto-stash" >/dev/null
fi

if gh pr merge "$PR_NUM" --squash --delete-branch; then
  MERGE_OK=true
else
  MERGE_OK=false
fi

if [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "true" ]; then
  if ! git stash pop; then
    echo "WARNING: stash pop conflicted. Your changes are preserved on the stash stack." >&2
    echo "Run \`git stash list\` to see the saved entry (message: flowkit-auto-stash) and \`git stash pop\` after resolving." >&2
  fi
elif [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "false" ]; then
  echo "WARNING: merge failed — stash preserved. Run \`git stash pop\` after resolving the merge error." >&2
fi

[ "$MERGE_OK" = "false" ] && exit 1
```

### 4. Report

Print a summary:

> Merged PR #N.


## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always squash-merge (never merge commit or rebase merge)
- Always delete the remote branch on merge (`--delete-branch`)
