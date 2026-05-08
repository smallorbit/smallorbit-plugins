---
name: merge-pr
description: Squash-merge the open PR for the current branch and delete the remote branch (retargets stacked children; clears blocking swarm worktrees).
triggers:
  - "/merge-pr"
  - "merge this PR"
  - "merge the PR"
  - "squash and merge"
allowed-tools: Bash
---

# merge-pr

Squash-merge the open PR for the current branch and delete the remote branch. Open PRs that use this PR’s head as their base are retargeted first so GitHub does not auto-close them when the head branch is deleted.

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

`scripts/merge_pr.sh` implements worktree cleanup, stacked-PR retargeting, and a `with-clean-workspace`–wrapped `gh pr merge --squash --delete-branch`. On success it prints **bare JSON** on stdout:

| Field | Type | Meaning |
| --- | --- | --- |
| `pr_number` | number | Merged PR |
| `head_branch` | string | PR head branch removed on the remote |
| `local_delete_failed` | boolean | Remote merge succeeded but local branch deletion failed |

Errors: non-zero exit, message on stderr only, stdout empty. See [`plugins/_shared/script-authoring.md`](../../../_shared/script-authoring.md).

## Constraints

- Never merge into `main` directly — this skill targets the default merge base only
- Always squash-merge (never merge commit or rebase merge)
- Always delete the remote branch on merge (`--delete-branch`)
