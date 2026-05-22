---
name: merge-pr
description: Rebase-merge the open PR for the current branch and delete the remote branch (retargets stacked children; clears blocking worktrees — auto-checks out base branch when the main worktree holds the head).
triggers:
  - "/merge-pr"
  - "merge this PR"
  - "merge the PR"
  - "rebase and merge"
allowed-tools: Bash
---

# merge-pr

Rebase-merge the open PR for the current branch and delete the remote branch. Open PRs that use this PR’s head as their base are retargeted first so GitHub does not auto-close them when the head branch is deleted.

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

`scripts/merge_pr.sh` implements worktree cleanup, stacked-PR retargeting, and a `with-clean-workspace`–wrapped `gh pr merge --rebase --delete-branch`. When the PR's head branch is held by a linked worktree the script removes it via `git worktree remove --force` — unless the caller's cwd is inside that worktree, in which case the script refuses with operator guidance to exit the worktree first (otherwise it would delete its own caller's working directory and cascade ENOENT errors through the rest of the session). When the branch is held by the main worktree (the canonical state after `push-or-pr`) the script instead runs `git checkout <base>` in the main worktree so the branch can be released without the operator needing to do it manually. On success it prints **bare JSON** on stdout:

| Field | Type | Meaning |
| --- | --- | --- |
| `pr_number` | number | Merged PR |
| `head_branch` | string | PR head branch removed on the remote |
| `local_delete_failed` | boolean | Remote merge succeeded but local branch deletion failed |

Errors: non-zero exit, message on stderr only, stdout empty. See [`plugins/_shared/script-authoring.md`](../../../_shared/script-authoring.md).

## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always rebase-merge (never squash or merge commit)
- Always delete the remote branch on merge (`--delete-branch`)
