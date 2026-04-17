---
name: pr
description: Wrap up existing changes and open a pull request. Combines create-branch, commit, and open-pr into a single workflow.
triggers:
  - "/pr"
  - "create a PR for this"
  - "open a pull request for"
  - "wrap this up as a PR"
allowed-tools: Bash
---

# PR

Convenience orchestrator that runs `/create-branch`, `/commit`, and `/open-pr` in sequence to take uncommitted workspace changes all the way to an open pull request.

## Input

`$ARGUMENTS` — description of the work. Used to name the branch, write the commit message, and title the PR. If omitted, each sub-skill infers from context.

## Process

### 1. Check current branch

```bash
git rev-parse --abbrev-ref HEAD
```

If the current branch is already a non-protected branch (not `develop`, `main`, `master`, or `staging`), skip step 2 and go directly to step 3.

### 2. Create branch (if on a protected branch)

Follow `/create-branch` with `$ARGUMENTS` to create and check out a new branch off `origin/develop`.

### 3. Commit changes

Follow `/commit` with `$ARGUMENTS` to stage and commit all current workspace changes using conventional commits.

If the workspace is already clean (nothing to commit), skip this step.

### 4. Open PR

Follow `/open-pr` with `$ARGUMENTS` to push the branch and open a GitHub pull request.

### 5. Report

Output the PR URL.

## Constraints

- Never skip the branch check — always detect whether you're already on a feature branch before creating a new one
- Each step delegates fully to its sub-skill; do not re-implement their logic inline
- If any step fails, stop and report the error — do not continue to the next step
- If the workspace is clean and no commits are needed, note this and proceed directly to `/open-pr`
