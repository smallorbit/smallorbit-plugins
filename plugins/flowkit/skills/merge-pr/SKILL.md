---
name: merge-pr
description: Squash-merge the open PR for the current branch and delete the remote branch. Squash-only — never rebase or merge-commit. Clears blocking worktrees and auto-checks out the base branch when the main worktree holds the head.
triggers:
  - "/merge-pr"
  - "merge this PR"
  - "merge the PR"
  - "squash and merge"
allowed-tools: Bash
---

# merge-pr

Squash-merge the open PR for the current branch and delete the remote branch. Under GitHub Flow with squash-merge, GitHub computes the squash server-side — no fast-forward requirement, no stacked-PR rebase-retargeting dance.

## Input

`$ARGUMENTS` — optional PR number. If omitted, auto-detects the open PR for the current branch.

## Process

1. Capture the skill directory from the harness header line:

   `Base directory for this skill: <absolute path>`

   ```bash
   export SKILL_DIR="<absolute path from the header line>"
   ```

2. Run the script (pass through optional PR number):

   ```bash
   RESULT=$(bash "$SKILL_DIR/scripts/merge_pr.sh" $ARGUMENTS)
   ```

3. On success (`RESULT` is non-empty JSON), print:

   > Merged PR #N.

   where `N` is `.pr_number` from `RESULT`.

   If `.local_delete_failed` is true, stderr already contains cleanup guidance; still report the merge as above.

4. On failure (script non-zero exit, empty stdout), surface stderr and stop.

## Script contract

`scripts/merge_pr.sh` implements worktree cleanup and a `with-clean-workspace`–wrapped `gh pr merge --squash --delete-branch`. The merge mode is squash, always — the script never accepts a `--rebase` or `--merge` argument and never invokes those modes.

When the PR's head branch is held by a linked worktree the script removes it via `git worktree remove --force` — unless the caller's cwd is inside that worktree, in which case the script refuses with operator guidance to exit the worktree first (otherwise it would delete its own caller's working directory and cascade ENOENT errors through the rest of the session). When the branch is held by the main worktree (the canonical state after `push-or-pr`) the script instead runs `git checkout <base>` in the main worktree so the branch can be released without the operator needing to do it manually.

On success it prints **bare JSON** on stdout:

| Field | Type | Meaning |
| --- | --- | --- |
| `pr_number` | number | Merged PR |
| `head_branch` | string | PR head branch removed on the remote |
| `local_delete_failed` | boolean | Remote merge succeeded but local branch deletion failed |

Errors: non-zero exit, message on stderr only, stdout empty. See [`plugins/_shared/script-authoring.md`](../../../_shared/script-authoring.md).

## Why squash-merge

GitHub Flow with squash-merge eliminates the rebase-merge invariant that v3 carried: GitHub computes the squash server-side, so a stacked PR whose base advances doesn't fail at merge time and doesn't need a local rebase + force-push to recover. Descendant PRs apply cleanly against the updated base on next merge attempt without any retargeting machinery on flowkit's side.

Squash-merge also collapses the per-PR commit history into a single commit on `main` with the PR body summary as the message body — preserving linear first-parent history and PR-granularity bisectability.
