---
name: merge-stack
description: Merge any PR stack bottom-up — defaulting to the swarm-produced worktree-agent-* PRs — after retargeting every non-root PR to the base branch, using a uniform squash-and-delete-branch strategy.
---

# merge-stack

Merges a stack of open PRs bottom-up — root PRs first, then their former children, up to the leaves. The default merge set is the swarm-produced `worktree-agent-*` PRs, but the selection layers below scope the run to any set of open PRs. Before any merge happens, every non-root PR in a multi-PR chain is retargeted to `$BASE` so GitHub never fires its auto-close cascade. Every PR then merges uniformly with `gh pr merge <N> --squash --delete-branch`, and each PR closes its own `Closes/Fixes/Resolves/Refs` references on merge.

Selection is the only step that ever looked at head-branch naming. Everything downstream — graph build, retarget, ordering, conflict handling, base sync — treats each PR as an ordinary topology node, so ad-hoc PRs (`fix/…`, `chore/…`) participate on identical terms once selected.

Because the underlying merge mode is squash, GitHub's tree-based diff handles already-applied predecessor commits automatically — no per-merge downstream rebase is required. If a downstream PR genuinely conflicts with the freshly-merged predecessor's content, the existing conflict-stops-chain rule (5d) marks it blocked and the operator resolves it manually.

## When to use

Merging two or more open PRs that sit in a base-relationship stack. The common case is right after `/swarm` finishes — agents have pushed branches and opened PRs, none have merged, and you've reviewed them. The same command also lands a hand-built stack, or a swarm plus the ad-hoc fix PRs you opened on top of it.

## Input

| Form | Effect |
|------|--------|
| *(no arguments)* | Swarm default — every open PR whose head branch starts with `worktree-agent-`. Auto-proceeds; `$BASE` is derived from the root PRs' `baseRefName`. |
| `<pr>...` | Exact set — merge precisely these PR numbers, replacing the swarm default. Each must exist and be open. |
| `--include <pr>...` | Extends whichever base set is in effect (swarm default or `--base` scope) with these PR numbers. PR numbers only — no branch names. Deduped against the set. |
| `--base <branch>` | Scopes selection to the stack rooted at `<branch>`, derived from base-relationship topology rather than head-branch naming. Replaces the swarm default and pins `<branch>` as the retarget target `$BASE`. Mutually exclusive with an exact positional set. |

There is no unscoped "all open PRs" mode. The set is always the swarm default, an exact positional set, or a `--base` scope — each optionally extended by `--include`.

Any set containing a non-`worktree-agent-*` PR requires explicit confirmation before merging (Step 4). A pure-swarm set proceeds immediately, exactly as a bare invocation always has.

## Process

### 1. Resolve the merge set

`select_prs.sh` owns the whole selection algebra: flag parsing, layer resolution, existence/open validation, dedupe, `$BASE` derivation, and pure-swarm-vs-mixed classification. Invalid flag combinations exit non-zero before anything is merged.

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
SELECTION=$("$SKILL_DIR/scripts/select_prs.sh" <user arguments verbatim>)
```

On non-zero exit, surface stderr to the user and stop. On success, read the fields:

| Field | Use |
|-------|-----|
| `prs` | `[{number, title, headRefName, baseRefName, is_swarm}]` — the merge set, sorted by number. |
| `pr_numbers` | The selected PR numbers. |
| `base` | Retarget target `$BASE`; `null` when the set has more than one distinct root base. |
| `base_pinned` | `true` when `$BASE` came from `--base` rather than derivation. |
| `base_candidates` | Distinct root bases in the set — use these per chain when `base` is `null`. |
| `merge_set_branches` | Every selected head-branch name. |
| `swarm_branches` | The `worktree-agent-*` subset — gates Step 4's pre-scan and Step 7's follow-up. |
| `non_swarm_prs` | Selected PRs outside the swarm convention. |
| `requires_confirmation` | `true` when the set is mixed — Step 4 must stop and ask. |

If `count` is `0`, report "No open PRs matched the selection" (for a bare invocation, "No open swarm PRs found") and stop.

### 2. Build the stack graph

Model the selected PRs as a directed graph where an edge A → B means "A's head branch is B's base branch" (A sits on top of B). Build this from the `headRefName` / `baseRefName` fields in `prs` — no issue-body parsing needed for ordering, and no head-branch naming assumptions. Ad-hoc PRs are ordinary nodes here.

`$BASE` is the `base` field from Step 1 — pinned by `--base` when `base_pinned` is `true`, otherwise derived from the root PRs' `baseRefName`. When `base` is `null` the set spans more than one root base; treat each entry in `base_candidates` as that chain's own `$BASE`.

Identify:
- **Root PRs**: PRs whose `baseRefName` is `$BASE` (e.g. `main`, or a `feature/<slug>-<N>` epic branch) and that have at least one other PR stacked on top — these merge first in their chain.
- **Leaves**: PRs whose `headRefName` is not the `baseRefName` of any other open PR — these are the tops of chains and merge last.
- **Independent PRs**: PRs whose `baseRefName` is already `$BASE` and that no other PR sits on top of — these have no stack relationship and can merge in any order.

For each chain, the merge order is: root → … → leaf (bottom-up).

### 3. Retarget non-root PRs to `$BASE`

For every multi-PR chain, retarget every non-root PR to `$BASE` before merging anything. This neutralizes GitHub's auto-close cascade: once a child's base is `$BASE`, deleting a predecessor's branch on merge no longer looks like abandonment.

```bash
gh pr edit <N> --base $BASE
```

Apply this to every PR in a multi-PR chain except the chain root. Independent PRs already target `$BASE` and need no retargeting. Track the retarget count for the plan preview and final report.

When `base` is `null` there is no single global `$BASE`. Resolve `$BASE` per chain: a chain's `$BASE` is its own root PR's `baseRefName` — the matching entry in `base_candidates` — and every non-root PR in that chain retargets to that value. Never retarget a chain onto another chain's root base.

### 4. Present merge plan

Before showing the plan, pre-scan local worktrees for any branch in the merge set. Skip this pre-scan entirely when `swarm_branches` is empty — only `worktree-agent-*` branches are ever held by agent worktrees, so a set without them has nothing to warn about.

`gh pr merge --delete-branch` prints a benign-but-confusing `failed to delete local branch ... used by worktree at ...` warning when a branch is held by an active worktree; the merge itself still succeeds and the remote branch is deleted. Forewarning the user keeps that warning from reading like a failure.

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

Where `$MERGE_SET_BRANCHES` is the newline-delimited `merge_set_branches` list from Step 1. If `git worktree list` fails for any reason, treat `HELD_BY_WORKTREE` as empty and proceed without the note.

Render the count + comma-joined list for the note:

```bash
HELD_COUNT=$(printf '%s' "$HELD_BY_WORKTREE" | grep -c .)
HELD_LIST=$(printf '%s' "$HELD_BY_WORKTREE" | tr '\n' ',' | sed 's/,$//;s/,/, /g')
```

Show the plan before proceeding. When `HELD_BY_WORKTREE` is non-empty, prepend the note inside the plan block (one line for the count, one for the warning context, one for the remediation):

```
Merge order (bottom-up per chain):
  Chain 1:  main ← PR #103 ← PR #104 ← PR #105
  Chain 2:  main ← PR #108  (independent)

  Retargeted 2 non-root PRs to main: #104, #105
  Step 1. Merge PR #103 into main (squash, delete branch)
  Step 2. Merge PR #104 into main (squash, delete branch)
  Step 3. Merge PR #105 into main (squash, delete branch)
  Step 4. Merge PR #108 into main (squash, delete branch)

  Note: 2 branches are held by worktrees (worktree-agent-1361, worktree-agent-1393).
  `gh pr merge --delete-branch` will warn but the merges will succeed.
  Run `/swarmkit:clean-worktrees` after to reap them.
```

When `requires_confirmation` is `false` — a pure-swarm set, which is what a bare invocation always resolves to — proceed immediately.

When `requires_confirmation` is `true`, the set contains PRs outside the swarm convention, so it was assembled by hand and merging it is not a routine post-swarm sweep. List the `non_swarm_prs` entries under the plan and stop for an explicit go-ahead:

```
  Selection includes 2 PRs outside the worktree-agent-* convention:
    #120  fix/typo     Fix broken anchor in README
    #134  fix/other    Correct base URL in docs

  These will be squash-merged and their branches deleted. Merge this set? (y/N)
```

Do not merge anything until the user confirms. Anything other than an explicit yes aborts the run with no changes made.

### 5. Merge bottom-up

For each chain, work from the root up to the leaf. Every `$BASE` reference below is that chain's own `$BASE`: when `base` is `null`, substitute the chain's entry from `base_candidates` rather than one global value — a PR merges into the base its own chain is rooted at.

For each PR in order:

#### 5a. Check mergeability

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
```

If `mergeStateStatus` is `UNKNOWN`, retry after a short sleep. If it is `DIRTY` or `CONFLICTING`, fall through to 5d (conflict handling) — squash-merge does not require fast-forward, so `BEHIND` alone is not blocking and the merge proceeds.

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

If a merge fails with `CONFLICTING` (or returns `DIRTY` from 5a):
- Stop the chain at this PR
- Report the conflict with the PR number and branch names
- Mark all PRs above it in the same chain as blocked
- Continue with any independent PRs or unrelated chains
- At the end, list all stopped and blocked PRs so the user can resolve and re-run

Squash-merge does not require predecessor commits to be present in the downstream branch's history — GitHub's tree-based diff drops already-applied predecessor content automatically. No per-merge downstream rebase is required.

#### 5e. Pause between merges

```bash
sleep 3
```

### 6. Sync base branch

After all merges:

```bash
git checkout $BASE
git pull origin $BASE
```

Where `$BASE` is the `base` field from Step 1 (typically `main`, the `feature/<slug>-<N>` branch when swarmkit pinned one, or the branch passed to `--base`). When `base` is `null` the set spanned multiple root bases — there is no single `$BASE` to sync, so repeat the checkout-and-pull once for every entry in `base_candidates`.

### 7. Report

Skip the `swarmkit:clean-worktrees` follow-up entirely when `swarm_branches` from Step 1 is empty — a set with no `worktree-agent-*` branches left no agent worktrees behind.

Otherwise append a follow-up suggestion that points the user at `swarmkit:clean-worktrees`. If any `worktree-agent-*` worktrees still exist, recommend running it; otherwise note that the worktrees are already gone:

```bash
if git worktree list --porcelain | awk '/^branch refs\/heads\/worktree-agent-/' | grep -q .; then
  FOLLOWUP="Next: /swarmkit:clean-worktrees   (remove worktrees + prune orphan local branches)"
else
  FOLLOWUP="(no worktree-agent-* worktrees remain — skip clean-worktrees)"
fi
```

```
── merge-stack complete ──────────────────────────────
✓ Retargeted 2 non-root PRs to main
✓ Merged (chain 1): PR #103 → PR #104 → PR #105 → main
✓ Merged (independent): PR #108 → main
✗ Conflicted: PR #107 — stopped mid-chain
⊘ Blocked: PR #106 — depends on #107

Next: /swarmkit:clean-worktrees   (remove worktrees + prune orphan local branches)
──────────────────────────────────────────────────────
```
