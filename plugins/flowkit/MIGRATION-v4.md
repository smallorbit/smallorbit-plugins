# Flowkit v3 → v4 Migration Guide

Flowkit v4 replaces the develop/RC/main multi-branch model with single-trunk [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow): feature branches → squash-merge to `main` → tag for release. This guide covers both the automated migration helper and the manual steps.

## What Changed

### Skills removed in v4

| Removed skill | v4 replacement |
|---------------|---------------|
| `/create-branch` | `git checkout -b <name>` directly |
| `/cut` | removed — no RC branches in v4 |
| `/release` | `/flowkit:ship` |
| `/ship-epic` | merge the epic branch PR via `/merge-pr`, then `/ship` |
| `/cut-epic` | `git checkout -b feature/<slug>-<N>` + `git config claude.flowkit.prBase` |
| `/pr-base-scope` | removed — set `claude.flowkit.prBase` directly |
| `/default-branch-prompt` | removed — v4 always uses `main` |
| `/restack` | removed — squash-merge doesn't need mid-stack rebasing |

### Skills updated in v4

| Skill | What changed |
|-------|-------------|
| `/ship` | Rewritten: preflight (main + sync + clean + commits since last tag) → semver derivation → annotated tag → GitHub Release. No release branch, no release PR. |
| `/merge-pr` | Squash-only. Drops rebase-onto-base and stacked-PR retargeting machinery. |
| `/pr` | One-shot: commit-if-dirty → open-pr against `main`. No `create-branch` step. |
| `/open-pr` | Default base is `main`; drops default-branch-prompt invocation. |
| `/sync` | Main-sync semantics: checkout `main`, pull, prune, delete merged locals. |
| `/pipeline-status` | Collapsed to in-flight PRs + released stages. No awaiting-cut or awaiting-release. |

### New in v4

| Skill | What it does |
|-------|-------------|
| `/migrate-v4` | Interactive migration helper — detects v3 state, presents a plan, executes with per-step confirmation. |

## Automated Migration

Run the interactive helper from any repo that still uses the v3 flow:

```
/flowkit:migrate-v4
```

The helper:
1. Detects legacy state (GitHub default = `develop`, `origin/develop` present, stale config keys, `rc/*` branches).
2. Presents the full migration plan (steps to run + informational items) and gates on a single "Proceed?" confirmation.
3. Executes per-step with individual confirmation on every destructive operation.

It is idempotent — running it on an already-migrated repo prints "Nothing to do — repo is on single-trunk main." and exits without mutation.

## Manual Migration

If you prefer to run the steps yourself:

### 1. Ensure `main` is current

```bash
git checkout main
git pull origin main
```

If your repo only has `develop` (no `main`), create it:

```bash
git checkout -b main develop
git push origin main
```

### 2. Merge `develop` into `main` (fast-forward if possible)

```bash
git merge develop --ff-only
git push origin main
```

If `develop` and `main` have diverged (non-fast-forward), check the bidirectional diff first:

```bash
git log main..develop --oneline   # commits on develop not on main
git log develop..main --oneline   # commits on main not on develop
```

Resolve any divergence manually before proceeding.

### 3. Switch the GitHub default branch to `main`

```bash
gh repo edit --default-branch main
```

This makes `Closes #N` keywords in PR bodies auto-close issues on merge to `main` going forward.

### 4. Delete `develop` remotely and locally

```bash
git push origin --delete develop
git branch -d develop
git fetch --prune
```

### 5. Clean up stale config keys

```bash
git config --unset claude.flowkit.defaultBranchPrompted 2>/dev/null || true
# Only unset prBase if it still points at develop (not an active epic):
git config --get claude.flowkit.prBase | grep -q develop && git config --unset claude.flowkit.prBase || true
```

### 6. Archive leftover `rc/*` and `feature/*` branches

`/migrate-v4` never auto-deletes these — they may contain unfinished work. Review manually:

```bash
git ls-remote --heads origin 'rc/*'
git ls-remote --heads origin 'feature/*'
```

For finished epics, delete them explicitly:

```bash
git push origin --delete feature/my-epic-1234
```

## Post-Migration Verification

After migrating, confirm:

```bash
# GitHub default branch is main
gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'
# → main

# No develop on origin
git ls-remote --heads origin develop
# → (empty)

# /flowkit:ship accepts the repo
# (dry-run: just read the preflight output before confirming the tag)
```

## Notes for Operators

- **Calver tags**: `/ship` can read and increment calver-style tags (`v2026.5.29`, `v2026.5.29.1`). No special handling needed.
- **Per-plugin tags**: The `{plugin}--v{version}` tags used by the smallorbit-plugins marketplace are unaffected. `/bump-versions` still creates them.
- **Open `feature/<slug>-<N>` branches**: Finish them (open the epic→main PR and merge) before or after migration. `/migrate-v4` surfaces them as informational; it never deletes them.
- **opsx-bridge / squadkit**: Both are updated in v4 to cut epic branches from `main` and default to `main` as the base branch. No operator action needed.
