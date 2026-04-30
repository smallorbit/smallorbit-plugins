---
name: clean-remote-worktrees
description: Sweep orphaned remote worktree-agent-* branches. Deletes only branches whose most-recent PR is merged; skips OPEN, CLOSED-not-merged, and no-PR branches. Complements swarmkit:clean-worktrees, which handles local state.
---

# Clean Remote Worktrees Skill

Sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs, crashed swarm runs, or merges that skipped `--delete-branch`.

Counterpart to `swarmkit:clean-worktrees` — this skill never touches local state.

## Arguments

Parse `$ARGUMENTS`:

- **No arguments** → **interactive**: classify, present plan, ask for confirmation before deletion
- `--yes` → **non-interactive**: skip confirmation (for automation contexts)

## Setup

**Resolve the skill base directory first.** Capture the runtime-resolved absolute path from the harness header (`Base directory for this skill: <absolute path>`):

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
```

Use `"$SKILL_DIR/scripts/..."` for every script invocation. Do **not** hardcode `plugins/swarmkit/...`.

## Process

### Step 1 — Classify remote branches

Run the classify script. It fetches and prunes origin, lists all remote `worktree-agent-*` branches, and buckets each by PR state in a single pass:

```bash
"$SKILL_DIR/scripts/classify.sh"
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "candidates": [
    {"branch": "worktree-agent-42", "pr_number": 210, "pr_title": "fix: ...", "state": "MERGED"},
    {"branch": "worktree-agent-43", "pr_number": 211, "pr_title": "feat: ...", "state": "OPEN"},
    {"branch": "worktree-agent-44", "pr_number": null, "pr_title": null, "state": "NO_PR"}
  ],
  "merged": ["worktree-agent-42"],
  "closed": [],
  "open": ["worktree-agent-43"],
  "no_pr": ["worktree-agent-44"]
}
```

If the script exits non-zero, surface stderr and stop.

### Step 2 — Check if there is anything to do

If `candidates` is an empty array, report:

> No remote `worktree-agent-*` branches found.

And stop.

If `merged` is empty, report the counts per bucket and stop:

```
Nothing to delete.

MERGED (to delete):  0
CLOSED (skipped):    <count>
OPEN (skipped):      <count>
No PR (skipped):     <count>
```

### Step 3 — Present the plan

Display the full classification to give the user visibility into what will and won't be touched:

```
MERGED (to delete):  <count>
  - worktree-agent-42

CLOSED (skipped):    <count>
  - worktree-agent-47
  ...

OPEN (skipped):      <count>
  - worktree-agent-101
  ...

No PR (skipped):     <count>
  - worktree-agent-55
  ...
```

### Step 4 — Confirm (interactive mode only)

In interactive mode (no `--yes`), ask before proceeding:

> Proceed with deleting **<count>** remote branch(es)?

Wait for user confirmation. If the user declines, stop without deleting anything.

With `--yes`, skip the prompt and proceed immediately.

### Step 5 — Delete merged branches

Run the delete script with the `merged` array from Step 1:

```bash
"$SKILL_DIR/scripts/delete.sh" --branches '<merged JSON array from classify output>'
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "deleted": ["worktree-agent-42"],
  "skipped": [],
  "errors": []
}
```

If the script exits non-zero, surface stderr and stop.

### Step 6 — Report

```
Deleted:  <count> remote branch(es)
  - worktree-agent-42
  ...

Skipped:  <count> branch(es)
  CLOSED (rejected work, preserved):
    - worktree-agent-47
  OPEN (active PR):
    - worktree-agent-101
  No PR (inspect manually):
    - worktree-agent-55

Errors: <list any errors; omit section if empty>
```

## Constraints

- Never delete a branch that is the head of an OPEN PR
- Never delete a branch whose most-recent PR is CLOSED (non-merged) — the branch contains rejected work that persists nowhere else
- Never delete a branch with no associated PR — surface it for manual inspection
- Always use refspec syntax (`git push origin :branch1 :branch2 ...`) for batch deletion; never loop `git push --delete` per branch (handled inside delete.sh)
- Never touch local state — worktrees and local branches are `swarmkit:clean-worktrees`'s concern
- Idempotent: running twice on a clean repo is a no-op
