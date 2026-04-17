---
name: merge-pr
description: Squash-merge the open PR for the current branch, delete the remote branch, and label referenced issues as merged-to-develop.
triggers:
  - "/merge-pr"
  - "merge this PR"
  - "merge the PR"
  - "squash and merge"
allowed-tools: Bash
---

# merge-pr

Squash-merge the open PR for the current branch, delete the remote branch, and apply the `merged-to-develop` label to any issues referenced in the PR body.

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

```bash
gh pr merge "$PR_NUM" --squash --delete-branch
```

### 4. Label referenced issues

Follow the `gh-label-merged-issues` sub-skill, passing `PR_NUM` as input. It will parse the PR body for `Closes/Fixes/Resolves #N` references and apply the `merged-to-develop` label to each referenced issue (skipping any with the `on-hold` label).

### 5. Report

Print a summary:

> Merged PR #N. Labeled issues: #X, #Y.

If no issues were referenced, omit the issues line.

## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always squash-merge (never merge commit or rebase merge)
- Always delete the remote branch on merge (`--delete-branch`)
