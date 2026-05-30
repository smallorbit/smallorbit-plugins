---
name: migrate-v4
description: Migrate a repository from flowkit v3 (develop/RC/main split) to flowkit v4 (single-trunk GitHub Flow on main). Interactive helper — detects legacy state, presents a plan, executes step-by-step with operator confirmation. Idempotent on already-migrated repos.
triggers:
  - "/flowkit:migrate-v4"
  - "migrate to v4"
  - "migrate to single-trunk"
  - "migrate flowkit v3 to v4"
allowed-tools: Bash, AskUserQuestion
---

# migrate-v4

One-time interactive migration from flowkit v3 (develop / RC / main with rebase-merge ceremony) to flowkit v4 (single-trunk GitHub Flow on `main`, squash-merge, no RC stage).

The migration is destructive (the GitHub default branch flips, `develop` gets deleted, legacy config keys get unset). Every destructive step prompts the operator. Re-running on an already-migrated repo is a no-op.

## Input

No arguments. The skill detects state from the live repo and the GitHub remote.

## Process

### 1. Detect legacy state

Read the repo's current shape — none of the commands below mutate anything.

```bash
# GitHub default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "")

# Origin branches
git fetch origin --quiet
DEVELOP_REMOTE=$(git ls-remote --heads origin develop | grep -c 'refs/heads/develop' || true)
MAIN_REMOTE=$(git ls-remote --heads origin main | grep -c 'refs/heads/main' || true)
RC_REMOTE=$(git ls-remote --heads origin 'rc/*' | awk '{print $2}' | sed 's@refs/heads/@@')
FEATURE_REMOTE=$(git ls-remote --heads origin 'feature/*' | awk '{print $2}' | sed 's@refs/heads/@@')

# Legacy config keys
DEFAULT_PROMPTED=$(git config --get claude.flowkit.defaultBranchPrompted || true)
PR_BASE=$(git config --get claude.flowkit.prBase || true)
PR_BASE_STALE=""
if [ -n "$PR_BASE" ] && ! git show-ref --verify --quiet "refs/heads/$PR_BASE" \
   && ! git ls-remote --heads origin "$PR_BASE" | grep -q "refs/heads/$PR_BASE"; then
  PR_BASE_STALE="$PR_BASE"
fi
```

A repo is **legacy** if any of these hold:

- `DEFAULT_BRANCH == "develop"`
- `DEVELOP_REMOTE > 0 && MAIN_REMOTE == 0`
- `DEFAULT_PROMPTED` is non-empty
- `RC_REMOTE` is non-empty

If none hold and no other legacy artifacts surface, the repo is already migrated — jump to step 6 (idempotent exit).

### 2. Assemble the migration plan

Build an ordered plan of the steps that will actually run, plus the informational items (RC and feature branches the operator must finish or delete manually). Example plan output:

```
flowkit v4 migration plan for <repo>:

Detected:
  - GitHub default branch: develop
  - origin/develop: present
  - origin/main: missing
  - claude.flowkit.defaultBranchPrompted: 1
  - rc/* branches on origin: rc/2025-04-12.1, rc/2025-04-19.1
  - feature/* branches on origin: feature/migration-981, feature/cleanup-984
  - claude.flowkit.prBase (stale): feature/migration-981

Steps that will run:
  1. Fetch origin develop and main (create local main if missing).
  2. Fast-forward main to develop's tip (git merge develop --ff-only).
  3. Push main to origin (git push origin main).
  4. Switch GitHub default branch to main (gh repo edit --default-branch main).
  5. Delete origin/develop (git push origin --delete develop).
  6. Delete local develop (git branch -D develop) — if present.
  7. Unset claude.flowkit.defaultBranchPrompted.
  8. Surface stale claude.flowkit.prBase (operator confirms before unset).

Informational (will NOT be auto-deleted):
  - rc/* branches: rc/2025-04-12.1, rc/2025-04-19.1
    → review and `git push origin --delete <branch>` once you're sure they hold nothing useful.
  - feature/* branches: feature/migration-981, feature/cleanup-984
    → these may contain unfinished work. Finish (merge or close), then delete manually.
```

### 3. Operator confirms the plan

Ask once, up-front, before any mutation:

> Proceed with this plan? (yes / no)

Use `AskUserQuestion` (or equivalent). If the operator answers anything other than "yes", abort cleanly without touching the repo.

### 4. Execute steps with per-step confirmation

Each destructive step is its own prompt. The operator can answer **yes** (run), **skip** (move on without running this step), or **abort** (stop immediately). Skipping a step does not skip subsequent steps — they are independent.

#### Step 4.1 — Fetch and ensure local main

Always-safe; no prompt needed beyond the plan-level confirm.

```bash
git fetch origin --quiet

if ! git show-ref --verify --quiet refs/heads/main; then
  if git ls-remote --heads origin main | grep -q 'refs/heads/main'; then
    git branch main origin/main
  else
    # No origin/main yet — base local main off origin/develop so step 4.2 has something to FF
    git branch main origin/develop
  fi
fi
```

#### Step 4.2 — Fast-forward main to develop

Prompt: "Fast-forward main to develop's tip?"

```bash
git checkout main

if git merge develop --ff-only 2>/dev/null; then
  echo "main fast-forwarded to develop."
else
  AHEAD=$(git rev-list --count develop..main)
  BEHIND=$(git rev-list --count main..develop)
  echo "main and develop have diverged:" >&2
  echo "  main is ahead of develop by $AHEAD commits" >&2
  echo "  main is behind develop by $BEHIND commits" >&2
  git log --oneline main..develop | head -20 >&2
  echo "" >&2
  echo "main..develop (commits only on develop):" >&2
  git log --oneline main..develop >&2
  echo "develop..main (commits only on main):" >&2
  git log --oneline develop..main >&2
fi
```

If the FF fails, surface the divergence and ask the operator how to proceed (abort / take develop's tip via reset / take main's tip / handle manually outside the skill). Do not auto-merge.

#### Step 4.3 — Push main

Prompt: "Push main to origin?"

```bash
git push origin main
```

#### Step 4.4 — Switch GitHub default branch to main

Prompt: "Switch the GitHub default branch from develop to main? This is destructive — open PRs targeting develop will need to be retargeted manually."

```bash
gh repo edit --default-branch main
```

#### Step 4.5 — Delete origin/develop

Prompt: "Delete origin/develop? Make sure no open PRs still target it."

```bash
git push origin --delete develop
```

#### Step 4.6 — Delete local develop

Prompt: "Delete the local develop branch?"

Only runs if the branch exists locally. Run after switching off it (step 4.2 already left HEAD on `main`).

```bash
if git show-ref --verify --quiet refs/heads/develop; then
  git branch -D develop
fi
```

#### Step 4.7 — Unset legacy config keys

Prompt: "Unset claude.flowkit.defaultBranchPrompted?" (only if it is currently set).

```bash
git config --unset claude.flowkit.defaultBranchPrompted
```

If `claude.flowkit.prBase` points at a branch that no longer exists (`PR_BASE_STALE` non-empty from step 1), surface it and prompt: "claude.flowkit.prBase points at <branch> which no longer exists. Unset it?"

```bash
git config --unset claude.flowkit.prBase
```

Never auto-unset a `prBase` that still resolves to a real branch — the operator may have pinned it deliberately.

#### Step 4.8 — Surface (do NOT delete) RC and feature branches

These are informational only. Print them with operator guidance; never delete:

- `rc/*` branches: report list, recommend `git push origin --delete <branch>` once verified.
- `feature/*` branches: report list, warn that they may contain unfinished work, recommend finishing or closing per branch before deletion.

### 5. Report

Print a summary:

- What ran (which steps the operator confirmed).
- What was skipped (steps the operator declined).
- What remains for manual cleanup (RC branches, feature branches, branch-protection rules on `develop`).
- The repo's new state: default branch, `origin/main` HEAD, absence of `develop`.

### 6. Idempotent exit

If detection in step 1 found no legacy artifacts:

```
Nothing to do — repo is on single-trunk main.
```

Exit zero without any mutation.

## Constraints

- The full plan MUST be shown before any mutation (no "decide as you go" flow).
- Each destructive step MUST prompt; the operator can skip individual steps or abort.
- `feature/<slug>-<N>` branches MUST NEVER be auto-deleted — they may hold unfinished work.
- `rc/*` branches are surfaced but not auto-deleted — the operator decides per-branch.
- `claude.flowkit.prBase` is only auto-unset when its target branch no longer exists, and only after operator confirmation.
- The skill MUST be idempotent — re-running on a migrated repo reports "nothing to do" and exits zero.
- Do not modify branch-protection rules; they are operator-owned policy. Surface their existence on `develop` as informational if relevant.
