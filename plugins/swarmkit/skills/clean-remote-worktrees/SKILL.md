---
name: clean-remote-worktrees
description: Sweep orphaned remote worktree-agent-* branches. Deletes only branches whose most-recent PR is merged; skips OPEN, CLOSED-not-merged, and no-PR branches. Complements swarmkit:clean-worktrees, which handles local state.
---

# Clean Remote Worktrees Skill

Sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs, crashed swarm runs, or merges that skipped `--delete-branch`.

Counterpart to `swarmkit:clean-worktrees` — this skill never touches local state.

## Arguments

Parse `$ARGUMENTS`:

- **No arguments** → **interactive**: fetch, classify, present plan, proceed to deletion on confirmation
- `--yes` → **non-interactive**: skip confirmation (for automation contexts)

## Process

1. **Fetch and prune** remote-tracking refs:
   ```bash
   git fetch origin --prune
   ```

2. **Enumerate candidates** — list every remote branch matching `worktree-agent-*` once, then reuse that list for classification:
   ```bash
   CANDIDATES=$(git ls-remote --heads origin 'worktree-agent-*' | awk '{print $2}' | sed 's|refs/heads/||')
   ```

   If `CANDIDATES` is empty, report "no remote worktree-agent-* branches" and exit.

3. **Classify each candidate** by the state of its most-recent PR. Pipe the candidate list into a `while read` loop (do not use `for BRANCH in $CANDIDATES` — word-splitting on newline-delimited output is unreliable):
   ```bash
   printf '%s\n' "$CANDIDATES" | while read BRANCH; do
     gh pr list --state all --head "$BRANCH" --json number,state,title --limit 1
   done
   ```

   Bucket each branch by its most-recent PR state:

   | Bucket | PR state | Action |
   |--------|----------|--------|
   | MERGED | `MERGED` | queue for deletion |
   | CLOSED | `CLOSED` (not merged) | skip — branch holds the only copy of rejected work |
   | OPEN | `OPEN` | skip — deletion would kill an active PR |
   | No PR | empty array | skip — could be crashed-run debris; surface for inspection |

4. **Present the plan** — counts per bucket, plus branch names in the three skipped buckets so the user can spot anything unexpected:
   ```
   MERGED (to delete): 12
   CLOSED (skipped):   2
     - worktree-agent-47
     - worktree-agent-89
   OPEN (skipped):     3
     - worktree-agent-101
     - worktree-agent-102
     - worktree-agent-103
   No PR (skipped):    1
     - worktree-agent-55
   ```

   If the MERGED bucket is empty, report and exit — nothing to delete.

   In interactive mode, ask for confirmation before proceeding. With `--yes`, proceed immediately.

5. **Delete all MERGED branches in a single push** — one refspec per branch, one network round-trip:
   ```bash
   git push origin :worktree-agent-12 :worktree-agent-15 :worktree-agent-18 ...
   ```

   Build the refspec list from the MERGED bucket. Do not loop per-branch — batch deletion is both faster and atomic in output.

6. **Report**:
   ```
   Deleted: 12 remote branches
   Skipped: 6 branches (2 CLOSED, 3 OPEN, 1 no-PR)

   Skipped branches:
     CLOSED (rejected work, preserved):
       - worktree-agent-47
       - worktree-agent-89
     OPEN (active PR):
       - worktree-agent-101
       ...
     No PR (inspect manually):
       - worktree-agent-55
   ```

## Constraints

- Never delete a branch that is the head of an OPEN PR
- Never delete a branch whose most-recent PR is CLOSED (non-merged) — the branch contains rejected work that persists nowhere else
- Always use refspec syntax (`git push origin :branch1 :branch2 ...`) for batch deletion; never loop `git push --delete` per branch
- Never touch local state — worktrees and local branches are `swarmkit:clean-worktrees`'s concern
- Idempotent: running twice on a clean repo is a no-op
