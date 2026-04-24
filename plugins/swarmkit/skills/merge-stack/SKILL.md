---
name: merge-stack
description: Merge all open swarm PRs bottom-up after retargeting every non-root PR to the base branch, using a uniform squash-and-delete-branch strategy.
---

# merge-stack

Merges all open swarm PRs bottom-up — root PRs first, then their former children, up to the leaves. Before any merge happens, every non-root PR in a multi-PR chain is retargeted to `$BASE` so GitHub never fires its auto-close cascade. Every PR then merges uniformly with `gh pr merge <N> --squash --delete-branch`, and each PR closes its own `Closes/Fixes/Resolves/Refs` references on merge.

This matches the merge direction used by Graphite, git-spice, Sapling, and Phabricator: reviewers see and land the same diff, CI runs once per PR instead of re-running on every rebase, and conflicts surface at the leaf instead of cascading down into the root.

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

Show the plan before proceeding:

```
Merge order (bottom-up per chain):
  Chain 1:  develop ← PR #103 ← PR #104 ← PR #105
  Chain 2:  develop ← PR #108  (independent)

  Retargeted 2 non-root PRs to develop: #104, #105
  Step 1. Merge PR #103 into develop (squash, delete branch)
  Step 2. Merge PR #104 into develop (squash, delete branch)
  Step 3. Merge PR #105 into develop (squash, delete branch)
  Step 4. Merge PR #108 into develop (squash, delete branch)
```

Proceed immediately.

### 5. Merge bottom-up

For each chain, work from the root up to the leaf. For each PR in order:

#### 5a. Check mergeability

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
```

If `mergeStateStatus` is `BEHIND`: update the branch and re-check:

```bash
gh pr update-branch <N>
sleep 3
```

#### 5b. Merge

Every PR uses the same strategy — uniform squash with branch deletion:

```bash
gh pr merge <N> --squash --delete-branch
```

Each PR's own body closes its own issues natively on merge. No ref injection, no body rewriting.

#### 5c. Conflict handling

If a merge fails with `CONFLICTING`:
- Stop the chain at this PR
- Report the conflict with the PR number and branch names
- Mark all PRs above it in the same chain as blocked
- Continue with any independent PRs or unrelated chains
- At the end, list all stopped and blocked PRs so the user can resolve and re-run

#### 5d. Pause between merges

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

```
── merge-stack complete ──────────────────────────────
✓ Retargeted 2 non-root PRs to develop
✓ Merged (chain 1): PR #103 → PR #104 → PR #105 → develop
✓ Merged (independent): PR #108 → develop
✗ Conflicted: PR #107 — stopped mid-chain
⊘ Blocked: PR #106 — depends on #107
──────────────────────────────────────────────────────
```

## Constraints

- Always merge bottom-up (root PRs first, leaves last)
- Always retarget every non-root PR in a multi-PR chain to `$BASE` before merging anything in that chain
- Use `gh pr merge <N> --squash --delete-branch` for every PR — no per-role strategy matrix
- Never merge into `main` directly — only into `$BASE` (e.g., `develop`)
- Never skip a conflicted chain's dependents — block and report them
- Independent PRs (targeting `$BASE` with nothing stacked on them) may merge in any order
