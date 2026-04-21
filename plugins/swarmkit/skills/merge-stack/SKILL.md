---
name: merge-stack
description: Merge all open swarm PRs top-down, accumulating issue refs as the stack collapses into the base branch.
---

# merge-stack

Merges all open swarm PRs top-down — leaf PRs first, cascading down to the base branch. Each merge injects the absorbed PR's `Closes` refs into the next PR's body so refs accumulate on the way down. The PR that finally merges into `$BASE` carries the complete ref set for the entire stack.

This avoids the auto-close cascade caused by bottom-up merging: merging bottom-up deletes the base branch of the PR above it, which GitHub interprets as abandonment and auto-closes the dependent PR.

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

### 2. Build the stack graph

Model the PRs as a directed graph where an edge A → B means "A's head branch is B's base branch" (A sits on top of B). Build this from the `headRefName` / `baseRefName` fields — no issue-body parsing needed for ordering.

Identify:
- **Leaves**: PRs whose `headRefName` is not the `baseRefName` of any other open PR — these are the tops of chains and merge first.
- **Root PRs**: PRs whose `baseRefName` is `$BASE` (e.g. `develop`) — these merge last.
- **Independent PRs**: PRs whose `baseRefName` is already `$BASE` and that no other PR sits on top of — these have no stack relationship and can merge in any order after stacked chains resolve.

For each chain, the merge order is: leaf → … → root (top-down).

### 3. Present merge plan

Show the plan before proceeding:

```
Merge order (top-down per chain):
  Chain 1:  PR #105 → PR #104 → PR #103 → develop
  Chain 2:  PR #108 → develop  (independent)

  Step 1. Merge PR #105 into worktree-agent-104 (head of chain 1)
  Step 2. Accumulate refs from #105 into PR #104 body
  Step 3. Merge PR #104 into worktree-agent-103
  Step 4. Accumulate refs from #104 into PR #103 body
  Step 5. Merge PR #103 into develop
  Step 6. Merge PR #108 into develop
```

Proceed immediately.

### 4. Merge top-down with ref accumulation

For each chain, work from the leaf down. For each PR in order:

#### 4a. Check mergeability

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
```

If `mergeStateStatus` is `BEHIND`: update the branch and re-check:

```bash
gh pr update-branch <N>
sleep 3
```

#### 4b. Collect this PR's issue refs

Extract all `Closes/Fixes/Resolves #N` references from the PR body:

```bash
REFS=$(echo "$PR_BODY" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | sort -u)
```

#### 4c. Merge — strategy depends on the PR's role in the stack

Three cases, each using a different strategy so that stacked PRs keep their individual commits on `$BASE` instead of being collapsed into a single squash commit:

```bash
# Intermediate merge (base is a worktree-agent-* branch)
# Rebase the leaf's commits onto its parent worktree-agent branch so each
# per-PR commit is preserved as the chain collapses downward.
# Omit --delete-branch so the base branch survives for the next merge step.
gh pr merge <N> --rebase

# Final merge into $BASE for the root of a multi-PR chain
# Use --merge so the accumulated stack lands as a merge commit preserving
# the per-PR commits underneath.
gh pr merge <N> --merge --delete-branch

# Final merge into $BASE for an independent (single-PR) chain
# No stack to preserve — squash to match flowkit's one-PR-one-commit convention.
gh pr merge <N> --squash --delete-branch
```

A PR is the "root of a multi-PR chain" iff its `baseRefName` is `$BASE` **and** at least one other open PR has this PR's `headRefName` as its `baseRefName` (i.e. something sits on top of it). A PR is "independent" iff its `baseRefName` is `$BASE` and nothing sits on top. Both distinctions were captured when building the stack graph in step 2.

#### 4d. Inject refs into the next PR down

After a non-root merge, append this PR's refs into the body of the PR immediately below it in the chain (the PR whose `headRefName` equals the just-merged PR's `baseRefName`):

```bash
NEXT_PR=<number of the PR below in the chain>
CURRENT_BODY=$(gh pr view $NEXT_PR --json body --jq '.body')
NEW_BODY="$CURRENT_BODY

$REFS"
gh pr edit $NEXT_PR --body "$NEW_BODY"
```

This ensures that if the merge halts mid-stack (conflict, failure), the surviving lowest unmerged PR already contains all refs from everything above it that successfully merged.

#### 4e. Conflict handling

If a merge fails with `CONFLICTING`:
- Stop the chain at this PR
- Report the conflict with the PR number and branch names
- Mark all PRs below it in the same chain as blocked
- Continue with any independent PRs or unrelated chains
- At the end, list all stopped and blocked PRs so the user can resolve and re-run

#### 4f. Pause between merges

```bash
sleep 3
```

#### 4g. Sweep intermediate remote branches

After the chain's root PR merges into `$BASE`, delete every intermediate `worktree-agent-*` branch from the remote. Intermediate branches are every `headRefName` whose `baseRefName` was another `worktree-agent-*` branch — these were captured when building the stack graph in step 2.

Run this sweep immediately after the root merge so partial runs still clean up the chains that did complete. Skip if there are no intermediate branches (single-PR chain or independent PR).

When the full list is available up front, batch the deletes into one push call to minimize round-trips. Fall back to per-branch deletes if the batch call fails (e.g. mixed stale refs):

```bash
if [ -n "$INTERMEDIATE_BRANCHES" ]; then
  echo "$INTERMEDIATE_BRANCHES" | while read branch; do
    git push origin --delete "$branch" 2>/dev/null || true
  done
fi
```

The `|| true` on each delete keeps a stale-ref failure from aborting the rest of the sweep. Track the count of swept branches for the report.

### 5. Sync base branch

After all merges:

```bash
git checkout $BASE
git pull origin $BASE
```

Where `$BASE` is the base branch of the root PRs (typically `develop`).

### 6. Report

```
── merge-stack complete ──────────────────────────────
✓ Merged (chain 1): PR #105 → #104 → #103 → develop
    Refs accumulated into PR #103: Closes #90, #91, #92, #93, #94
    Swept 2 intermediate remote branches (worktree-agent-105, worktree-agent-104)
✓ Merged (independent): PR #108 → develop
✗ Conflicted: PR #107 — stopped mid-chain
⊘ Blocked: PR #106 — depends on #107
──────────────────────────────────────────────────────
```

## Constraints

- Always merge top-down (leaf PRs first, root last)
- Use `--rebase` for intermediate merges, `--merge` for the root of a multi-PR chain, `--squash` for independent single-PR chains — never collapse a stack with a single squash
- Never use `--delete-branch` on intermediate merges — only on the final merge into `$BASE`
- Always accumulate refs downward after each intermediate merge
- Never merge into `main` directly — only into `$BASE` (e.g., `develop`)
- Never skip a conflicted chain's dependents — block and report them
- Independent PRs (targeting `$BASE` with nothing stacked on them) may merge in any order
- After a chain's root PR merges, delete every intermediate `worktree-agent-*` branch from the remote — their only purpose was to host the stack, and they are redundant once the root is in `$BASE`
