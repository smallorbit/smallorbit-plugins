---
name: clean-worktrees
description: Remove all agent worktrees and their orphaned local branches (worktree-agent-* prefix). Sub-skill used by swarm for post-run cleanup.
---

# Clean Worktrees Skill

Remove all agent worktrees and their orphaned local branches.

## Process

0. Capture the current branch: run `git branch --show-current` and store the result as `<caller-branch>`
1. Run `git worktree list` to find all worktrees
2. For each worktree that is NOT the main working directory:
   - Run `git worktree remove <path> --force`
   - If the command fails (exit code non-zero): report the path and error, continue to the next worktree — do not abort
3. Run `git worktree prune` to clean up stale worktree references
4. Find and delete orphaned local branches left by worktrees:
   - Run `git branch --format='%(refname:short)'` to list all local branches (avoids `*`/`+` markers in raw `git branch` output)
   - Filter for branches starting with `worktree-agent-`
   - Before deleting, cross-reference each target branch against `git worktree list` output. If any target branch is still checked out by an active worktree, **stop immediately** — report the stuck worktree path and branch name so the user can decide how to proceed. Do not attempt deletion of any remaining branches.
   - Delete each safe branch with `git branch -D <branch>`
   - Note: `swarm` names all agent branches with this prefix by convention
5. Report what was cleaned:
   - Number of worktrees removed
   - Number of branches deleted
   - If any worktree removals failed: list the paths so the user can resolve them manually
   - If nothing to clean, say so
   - Whether the caller's branch was restored or skipped (with the branch name)
6. Restore the caller's branch:
   - Check whether `<caller-branch>` still exists: run `git branch --list <caller-branch>`
   - If it exists: run `git checkout <caller-branch>`
   - If it no longer exists: skip the restore and warn the user that `<caller-branch>` was removed as part of the cleanup

## Constraints

- Never remove the main working directory — only non-main worktrees
- Never abort on a single worktree removal failure — always continue and report failures at the end
- If any orphaned branch is still checked out by an active worktree, stop and report — do not attempt deletion
- Always run `git worktree prune` after removals to clear stale references
- Always attempt to restore the caller's branch after cleanup; warn instead of erroring if the branch no longer exists
