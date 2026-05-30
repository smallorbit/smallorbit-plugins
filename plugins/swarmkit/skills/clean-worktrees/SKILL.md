---
name: clean-worktrees
description: Remove all agent worktrees and their orphaned local branches (worktree-agent-* prefix). Sub-skill used by swarm for post-run cleanup.
---

# Clean Worktrees Skill

Remove all agent worktrees and their orphaned local branches.

For remote branch cleanup, see `swarmkit:clean-remote-worktrees`.

## Setup

Capture the harness-emitted `Base directory for this skill:` path as `SKILL_DIR`; use `"$SKILL_DIR/scripts/..."` for every script invocation.

## Process

### Step 1 — Gather state

Run the gather script to enumerate what would be removed:

```bash
"$SKILL_DIR/scripts/gather.sh"
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "caller_branch": "main",
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

### Step 4 — Perform removal

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

If the script exits non-zero, surface stderr and stop. (The script refuses with operator guidance if the caller's cwd is inside any of the worktrees listed for removal — exit the worktree first.)

### Step 5 — Report

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

