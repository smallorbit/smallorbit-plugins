---
name: clean-worktrees
description: Remove all agent worktrees and their orphaned local branches (worktree-agent-* prefix). Sub-skill used by swarm for post-run cleanup.
---

# Clean Worktrees Skill

Remove all agent worktrees and their orphaned local branches.

For remote branch cleanup, see `swarmkit:clean-remote-worktrees`.

## Setup

**Resolve the skill base directory first.** Capture the runtime-resolved absolute path from the harness header (`Base directory for this skill: <absolute path>`):

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
```

Use `"$SKILL_DIR/scripts/..."` for every script invocation. Do **not** hardcode `plugins/swarmkit/...`.

## Process

### Step 1 — Gather state

Run the gather script to enumerate what would be removed:

```bash
"$SKILL_DIR/scripts/gather.sh"
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "caller_branch": "develop",
  "main_worktree": "/abs/path/to/repo",
  "worktrees_to_remove": [{"path": "/abs/path/to/repo/.claude/worktrees/worktree-agent-42"}],
  "branches_to_delete": ["worktree-agent-42", "worktree-agent-43"],
  "stuck": []
}
```

If the script exits non-zero, surface stderr and stop.

### Step 2 — Check for stuck worktrees

Parse the `stuck` array. If it is non-empty, **stop immediately** and report:

> The following branches are still checked out by active worktrees — cannot delete:
>
> - `<branch>` (worktree still active)
>
> Remove or force-stop those worktrees manually before re-running clean-worktrees.

Do **not** proceed to removal if `stuck` is non-empty.

### Step 3 — Check if there is anything to do

If both `worktrees_to_remove` and `branches_to_delete` are empty arrays, report:

> Nothing to clean — no agent worktrees or orphaned branches found.

And stop.

### Step 4 — Present plan and confirm

Summarize what will happen:

```
Worktrees to remove: <count>
  - /path/to/worktree-agent-42
  ...
Branches to delete: <count>
  - worktree-agent-42
  ...
```

Proceed immediately (no confirmation prompt needed for this automated cleanup step).

### Step 5 — Perform removal

Run the remove script with the gathered state:

```bash
"$SKILL_DIR/scripts/remove.sh" \
  --main-worktree "<main_worktree from gather output>" \
  --caller-branch "<caller_branch from gather output>" \
  --worktrees '<worktrees_to_remove JSON array from gather output>' \
  --branches '<branches_to_delete JSON array from gather output>'
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "removed": ["/abs/path/worktree-agent-42"],
  "remove_errors": [],
  "pruned_branches": ["worktree-agent-42", "worktree-agent-43"],
  "branch_errors": [],
  "caller_branch_restored": true
}
```

If the script exits non-zero, surface stderr and stop.

### Step 6 — Report

Parse the JSON and produce a clean summary:

```
Cleaned:
  Worktrees removed:  <count>  (<list of paths, or "none">)
  Branches deleted:   <count>  (<list of branches, or "none">)
  Caller branch:      restored to <caller_branch> / skipped (branch was removed)

Errors:
  <list any remove_errors or branch_errors; omit section if both are empty>
```

If `caller_branch_restored` is `false` and there were no errors, warn:

> `<caller_branch>` was removed as part of cleanup — no branch to restore to.

## Constraints

- Never remove the main working directory — only non-main worktrees
- Never abort on a single worktree removal failure — always continue and report failures at the end
- If any orphaned branch is still checked out by an active worktree, stop and report — do not attempt deletion
- Always run `git worktree prune` both before the removal loop and after removals to clear stale references (handled inside the scripts)
- Use `git worktree remove <path> -f -f` (double-force) to handle agent-locked worktrees (handled inside remove.sh)
- Always attempt to restore the caller's branch after cleanup; warn instead of erroring if the branch no longer exists
