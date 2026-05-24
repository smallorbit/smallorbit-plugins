---
name: merge-stack
description: Merge all open swarm PRs bottom-up after retargeting every non-root PR to the base branch, using a uniform squash-and-delete-branch strategy.
---

# merge-stack

Merges all open swarm PRs bottom-up — root PRs first, then their former children, up to the leaves. Before any merge happens, every non-root PR in a multi-PR chain is retargeted to `$BASE` so GitHub never fires its auto-close cascade. Every PR then merges uniformly with `gh pr merge <N> --squash --delete-branch`, and each PR closes its own `Closes/Fixes/Resolves/Refs` references on merge.

Between merges, each still-open downstream branch is locally rebased onto the freshly-updated `$BASE` and force-pushed. Git's patch-id matching drops the predecessor commits (which are already on `$BASE` in squashed form under a different SHA), leaving only the downstream PR's own new commits. Without this rebase, the next PR would flip to `CONFLICTING` the moment its predecessor merges, because the old predecessor commits in its history collide with the new squash commit on `$BASE`.

## When to use

Run after `/swarm` finishes. All swarm agents have pushed branches and opened PRs; none have merged yet. You've reviewed the PRs and are ready to merge them.

## Process

### 1. Find open swarm PRs

List all open PRs whose head branch starts with `worktree-agent-`:

```bash
gh pr list --state open --json number,title,headRefName,baseRefName,body \
  --jq '.[] | select(.headRefName | startswith("worktree-agent-"))'
```

If no open swarm PRs are found, report "No open swarm PRs found" and stop.

Capture the set of head-branch names — Step 4's worktree pre-scan needs it:

```bash
MERGE_SET_BRANCHES=$(gh pr list --state open --json headRefName \
  --jq '.[] | select(.headRefName | startswith("worktree-agent-")) | .headRefName')
```

### 2. Build the stack graph

Model the PRs as a directed graph where an edge A → B means "A's head branch is B's base branch" (A sits on top of B). Build this from the `headRefName` / `baseRefName` fields — no issue-body parsing needed for ordering.

Identify:
- **Root PRs**: PRs whose `baseRefName` is `$BASE` (e.g. `develop`) and that have at least one other PR stacked on top — these merge first in their chain.
- **Leaves**: PRs whose `headRefName` is not the `baseRefName` of any other open PR — these are the tops of chains and merge last.
- **Independent PRs**: PRs whose `baseRefName` is already `$BASE` and that no other PR sits on top of — these have no stack relationship and can merge in any order.

For each chain, the merge order is: root → … → leaf (bottom-up).

### 3. Retarget non-root PRs to `$BASE`

For every multi-PR chain, retarget every non-root PR to `$BASE` before merging anything. This neutralizes GitHub's auto-close cascade: once a child's base is `$BASE`, deleting a predecessor's branch on merge no longer looks like abandonment.

```bash
gh pr edit <N> --base $BASE
```

Apply this to every PR in a multi-PR chain except the chain root. Independent PRs already target `$BASE` and need no retargeting. Track the retarget count for the plan preview and final report.

### 4. Present merge plan

Before showing the plan, pre-scan local worktrees for any branch in the merge set. `gh pr merge --delete-branch` prints a benign-but-confusing `failed to delete local branch ... used by worktree at ...` warning when a branch is held by an active worktree; the merge itself still succeeds and the remote branch is deleted. Forewarning the user keeps that warning from reading like a failure.

The pre-scan is read-only — never remove worktrees here. Worktree reaping is `swarmkit:clean-worktrees`'s job.

```bash
HELD_BY_WORKTREE=$(git worktree list --porcelain \
  | awk '/^branch refs\/heads\// {sub("refs/heads/", "", $2); print $2}' \
  | grep -E '^worktree-agent-' \
  | while read -r branch; do
      if printf '%s\n' "$MERGE_SET_BRANCHES" | grep -Fxq -- "$branch"; then
        printf '%s\n' "$branch"
      fi
    done)
```

Where `$MERGE_SET_BRANCHES` is the newline-delimited list of `headRefName`s collected in step 1. If `git worktree list` fails for any reason, treat `HELD_BY_WORKTREE` as empty and proceed without the note.

Render the count + comma-joined list for the note:

```bash
HELD_COUNT=$(printf '%s' "$HELD_BY_WORKTREE" | grep -c .)
HELD_LIST=$(printf '%s' "$HELD_BY_WORKTREE" | tr '\n' ',' | sed 's/,$//;s/,/, /g')
```

Show the plan before proceeding. When `HELD_BY_WORKTREE` is non-empty, prepend the note inside the plan block (one line for the count, one for the warning context, one for the remediation):

```
Merge order (bottom-up per chain):
  Chain 1:  develop ← PR #103 ← PR #104 ← PR #105
  Chain 2:  develop ← PR #108  (independent)

  Retargeted 2 non-root PRs to develop: #104, #105
  Step 1. Merge PR #103 into develop (squash, delete branch)
  Step 2. Rebase #104, #105 onto develop (drop #103's commits via patch-id)
  Step 3. Merge PR #104 into develop (squash, delete branch)
  Step 4. Rebase #105 onto develop (drop #104's commits via patch-id)
  Step 5. Merge PR #105 into develop (squash, delete branch)
  Step 6. Merge PR #108 into develop (squash, delete branch)

  Note: 2 branches are held by worktrees (worktree-agent-1361, worktree-agent-1393).
  `gh pr merge --delete-branch` will warn but the merges will succeed.
  Run `/swarmkit:clean-worktrees` after to reap them.
```

Proceed immediately.

### 5. Merge bottom-up

For each chain, work from the root up to the leaf. For each PR in order:

#### 5a. Check mergeability

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
```

If `mergeStateStatus` is `BEHIND` (or `UNKNOWN` — retry after a short sleep): run the local rebase step from 5e against this branch, then re-check.

#### 5b. Warn on broken closing-keyword footers

Each PR's own body closes its own issues natively on merge, so a malformed footer is silently lossy — the merge succeeds and the trailing refs stay open. Before merging, scan the body for the space-separated form and warn:

```bash
BODY=$(gh pr view <N> --json body --jq '.body')
if printf '%s\n' "$BODY" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+[[:space:]]+#[0-9]+'; then
  echo "WARNING: PR #<N> body contains a space-separated closing-keyword footer (e.g. 'Closes #A #B #C')." >&2
  echo "GitHub will only auto-close the first ref; the rest will stay open after merge." >&2
  echo "Consider editing the PR body (one 'Closes #N' per line) before merging." >&2
fi
```

Warn-only — do not block. Merge-stack runs after review and the operator may choose to fix the trailing issues by hand.

#### 5c. Merge

Every PR uses the same strategy — uniform squash with branch deletion:

```bash
gh pr merge <N> --squash --delete-branch
```

Each PR's own body closes its own issues natively on merge. No ref injection, no body rewriting.

#### 5d. Conflict handling

If a merge fails with `CONFLICTING`, or if the rebase in 5e fails with a genuine content conflict (not a patch-id-matchable duplicate):
- Stop the chain at this PR
- Report the conflict with the PR number and branch names
- Mark all PRs above it in the same chain as blocked
- Continue with any independent PRs or unrelated chains
- At the end, list all stopped and blocked PRs so the user can resolve and re-run

#### 5e. Rebase downstream PRs before merging the next one

After merging a non-leaf PR in a chain, every still-open downstream PR in that chain has its predecessor's commits in its history under the old (pre-squash) SHAs. `$BASE` now carries the same content under a new squash SHA, so GitHub will flag the next PR as `DIRTY`/`CONFLICTING` even though the content overlap is benign. `gh pr update-branch` cannot resolve this — it fails with `Cannot update PR branch due to conflicts`. A local rebase is required because only `git rebase`'s patch-id matching drops the already-applied commits.

For every still-open PR in the chain, from closest-to-root to leaf:

```bash
RESTACK_SH="plugins/flowkit/skills/restack/scripts/restack.sh"
bash "$RESTACK_SH" --branch "<head-branch>" --upstream "origin/$BASE"
```

Implementation lives at [`flowkit:restack`](../../../flowkit/skills/restack/SKILL.md). The same script powers `/restack --pr N` for mid-review use.

`git rebase` will emit `warning: skipped previously applied commit <sha>` for each predecessor commit it drops via patch-id — that's the expected happy path, not an error. A non-zero exit from `git rebase` means a real merge conflict git could not auto-resolve; handle it per 5d. Always `git rebase --abort` before falling through so the branch returns to its pre-rebase state and no partial work is pushed.

After the rebases, re-query `mergeStateStatus` for the next PR to merge and proceed to 5c. GitHub may report `UNKNOWN` briefly after a force-push; poll with `sleep 3` until it resolves to `CLEAN`, `BEHIND`, or `DIRTY`.

For independent PRs (no chain), skip this step — they target `$BASE` directly and have no predecessor commits to drop.

#### 5f. Pause between merges

```bash
sleep 3
```

### 6. Sync base branch

After all merges:

```bash
git checkout $BASE
git pull origin $BASE
```

Where `$BASE` is the base branch of the root PRs (typically `develop`).

### 7. Report


Append a follow-up suggestion that points the user at `swarmkit:clean-worktrees`. If any `worktree-agent-*` worktrees still exist, recommend running it; otherwise note that the worktrees are already gone:

```bash
if git worktree list --porcelain | awk '/^branch refs\/heads\/worktree-agent-/' | grep -q .; then
  FOLLOWUP="Next: /swarmkit:clean-worktrees   (remove worktrees + prune orphan local branches)"
else
  FOLLOWUP="(no worktree-agent-* worktrees remain — skip clean-worktrees)"
fi
```

```
── merge-stack complete ──────────────────────────────
✓ Retargeted 2 non-root PRs to develop
✓ Merged (chain 1): PR #103 → PR #104 → PR #105 → develop
✓ Merged (independent): PR #108 → develop
✗ Conflicted: PR #107 — stopped mid-chain
⊘ Blocked: PR #106 — depends on #107

Next: /swarmkit:clean-worktrees   (remove worktrees + prune orphan local branches)
──────────────────────────────────────────────────────
```
