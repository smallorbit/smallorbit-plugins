---
name: clean-worktrees
description: Remove all agent worktrees and their orphaned local branches (worktree-agent-* prefix). Sub-skill used by swarm for post-run cleanup.
---

# Clean Worktrees Skill

Remove all agent worktrees and their orphaned local branches.

For remote branch cleanup, see `swarmkit:clean-remote-worktrees`.

## Process

0. Capture the current branch: run `git branch --show-current` and store the result as `<caller-branch>`
0.5. Run `git worktree prune` to clear any already-deleted worktree references before the removal loop begins
0.6. Derive the main worktree path and cd to it so subsequent git commands are not issued from a worktree directory that may itself be removed:
   ```bash
   MAIN_WORKTREE=$(git worktree list --porcelain | grep '^worktree' | head -1 | awk '{print $2}')
   cd "$MAIN_WORKTREE"
   ```
1. Run `git worktree list` to find all worktrees
2. For each worktree that is NOT the main working directory:
   - Run `git worktree remove <path> -f -f` (double-force) to handle agent-locked worktrees
   - If the command fails (exit code non-zero): report the path and error, continue to the next worktree — do not abort
3. Run `git worktree prune` to clean up any remaining stale worktree references
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
- Always run `git worktree prune` both before the removal loop (step 0.5) and after removals (step 3) to clear stale references
- Always cd to the main worktree root (step 0.6) before running the removal loop to avoid stale CWD errors when the caller's own worktree directory is removed
- Use `git worktree remove <path> -f -f` (double-force) to handle agent-locked worktrees that a single `--force` cannot remove
- Always attempt to restore the caller's branch after cleanup; warn instead of erroring if the branch no longer exists
