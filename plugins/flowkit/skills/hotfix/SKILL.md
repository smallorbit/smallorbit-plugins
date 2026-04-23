---
name: hotfix
description: Emergency fix bypassing develop — branch off main, apply fix, PR to main, tag, and back-merge into develop.
triggers:
  - "/hotfix"
  - "hotfix"
  - "emergency fix"
  - "patch main"
allowed-tools: Bash
---

# Hotfix

Apply an emergency fix directly to `main`, bypassing the normal `develop` cycle. Tags the fix on main and back-merges into develop to keep branches in sync.

## Input

`$ARGUMENTS` — description of the fix (required for branch naming and commit message). Example: "fix login crash on nil user".

## Process

### 1. Sync main

Follow the `git-sync-main` sub-skill: check out `main` and pull the latest from origin.

### 2. Create the hotfix branch

Derive a kebab-case slug from `$ARGUMENTS` (e.g. `"fix login crash"` → `"fix-login-crash"`):

```bash
git checkout -b "hotfix/$(date +%Y-%m-%d)-<slug-from-args>" origin/main
```

### 3. Wait for the user to apply the fix

Stop and prompt:

> Ready on hotfix branch. Make your fix, then say 'done' to continue.

Do not proceed until the user explicitly confirms the fix is in place.

### 4. Commit

Follow `/commit` with `$ARGUMENTS` as context for the commit message.

### 5. Detect staging

```bash
git fetch origin
git ls-remote --exit-code origin staging &>/dev/null && STAGING_EXISTS=true || STAGING_EXISTS=false
```

### 6. Scope the PR base to main

Follow the `pr-base-scope` sub-skill to set `claude.prBase = main`.

### 7. Open a PR targeting main

Follow `/open-pr`. Because `claude.prBase = main`, the PR targets `main`.

### 8. Merge the PR into main

Follow `/merge-pr` to squash-merge the hotfix PR into `main`.

### 9. Unset the PR base scope

Follow the `pr-base-scope` sub-skill to unset `claude.prBase`.

### 10. Tag the hotfix on main

Tag the hotfix directly on main using the same CalVer MICRO-increment scheme as `/release`, so hotfix tags sort naturally alongside planned release tags. A companion `hotfix/` tag at the same commit preserves discoverability via `git tag --list 'hotfix/*'`.

```bash
BASE_TAG="v$(date +%Y.%-m.%-d)"
N=1
TAG="$BASE_TAG"
while git ls-remote --exit-code origin "refs/tags/$TAG" &>/dev/null; do
  TAG="$BASE_TAG.$N"
  N=$((N + 1))
done
git tag -a "$TAG" main -m "Hotfix: <one-line reason from PR title>"
git push origin "$TAG"

COMPANION="hotfix/$TAG"
git tag "$COMPANION" "$TAG"
git push origin "$COMPANION"
```

The annotation message preserves the "hotfix" signal for `git tag -n` queries; the companion tag keeps the canonical version tag clean while still flagging the commit as an emergency fix.

### 11. Close referenced issues

Follow the `gh-close-referenced-issues` sub-skill, passing the merged PR number.

### 12. Back-merge main into develop

Keep `develop` in sync with the hotfix:

```bash
git fetch origin
git checkout develop
git pull origin develop
git merge --no-ff origin/main -m "chore(develop): back-merge hotfix from main"
git push origin develop
```

### 13. Sync develop

Follow the `git-sync-develop` sub-skill to confirm a clean local develop state.

### 14. Report

Summarize:
- Hotfix PR merged into main
- Tags created (include both the canonical version tag and the `hotfix/` companion tag)
- Referenced issues closed
- develop updated with back-merge

## Constraints

- Always wait for user confirmation between branch creation (step 2) and committing (step 4)
- Always back-merge main into develop after the hotfix merges
- Tag directly on main — do not run a full RC cycle for hotfixes
- No simplify pass — hotfix is an emergency flow
- If any step fails, stop and report clearly — do not continue
