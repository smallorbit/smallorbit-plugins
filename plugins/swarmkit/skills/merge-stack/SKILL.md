---
name: merge-stack
description: Merge all open swarm PRs bottom-up in dependency order. Used after swarmkit:swarm completes to cascade-merge the stacked PR chain.
---

# merge-stack

Merges all open swarm PRs in dependency order — bottom-up, so the most foundational PRs merge first and GitHub automatically retargets dependent PRs to `$BASE` as each merge completes.

## When to use

Run after `/swarm` finishes. All swarm agents have pushed branches and opened PRs; none have merged yet. You've reviewed the PRs and are ready to land them.

## Process

### 1. Find open swarm PRs

List all open PRs whose head branch starts with `worktree-agent-`:

```bash
gh pr list --state open --json number,title,headRefName,baseRefName,body \
  --jq '.[] | select(.headRefName | startswith("worktree-agent-"))'
```

If no open swarm PRs are found, report "No open swarm PRs found" and stop.

### 2. Reconstruct dependency order

For each PR, extract the issue number it closes from the body (`Closes #N`):

```bash
echo "$PR_BODY" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | grep -oE '[0-9]+'
```

Fetch each referenced issue body to extract dependency edges:

```bash
gh issue view <N> --json body --jq '.body' | grep -oiE '(depends on|blocked by) #[0-9]+' | grep -oE '[0-9]+'
```

Build a DAG from these edges. Produce a topological sort: PRs with no dependencies (or whose dependencies are already merged) come first.

### 3. Present merge plan

Show the merge order before proceeding:

```
Merge order (bottom-up):
  1. PR #103 → closes #90 (no deps)
  2. PR #105 → closes #91 (deps: #90)
  3. PR #106 → closes #94 (deps: #90, #91, #93)
```

Proceed immediately.

### 4. Merge in order

For each PR in the sorted order:

1. Check mergeability:
   ```bash
   gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
   ```

2. If `mergeStateStatus` is `BEHIND` (base has moved): update the branch:
   ```bash
   gh pr update-branch <N>
   ```
   Wait a moment and re-check before merging.

3. Merge:
   ```bash
   gh pr merge <N> --squash --delete-branch
   ```

4. After each merge, pause briefly for GitHub to retarget dependent PRs:
   ```bash
   sleep 3
   ```

5. If a merge fails with `CONFLICTING`:
   - Report the conflict clearly
   - Skip this PR and all PRs that depend on it
   - Continue merging independent PRs
   - At the end, list all skipped PRs and their dependents

### 5. Sync base branch

After all merges:

```bash
git checkout $BASE
git pull origin $BASE
```

Where `$BASE` is the base branch of the first merged PR (typically `develop`).

### 6. Report

```
── merge-stack complete ──────────────────
✓ Merged: PR #103 (#90), PR #104 (#91), PR #105 (#94)
✗ Conflicted: PR #106 (#97) — skipped
⊘ Blocked: PR #107 (#98) — depends on #97
─────────────────────────────────────────
```

## Constraints

- Always merge bottom-up (most depended-upon first)
- Never skip a conflict's dependents — always block them and report
- Never merge into `main` directly — only into `$BASE` (e.g., `develop`)
- If the merge order cannot be determined (no issue references), merge PRs targeting `$BASE` first, then stacked PRs in any order
