---
name: stage
description: Force-reset the staging branch to a release candidate. Graceful no-op if origin/staging does not exist.
triggers:
  - "/stage"
  - "push to staging"
  - "deploy to staging"
  - "stage this RC"
allowed-tools: Bash
---

# Stage

Force-reset `origin/staging` to point at a release candidate branch.

## Input

`$ARGUMENTS` — optional RC branch name (e.g. `rc/2026-04-16.1`). If omitted, the RC is auto-detected from the current branch or the most recent RC on origin.

## Process

### 1. Determine RC branch

Resolution order:

1. If `$ARGUMENTS` is provided, use it as the RC branch name.
2. Else if the current branch matches `rc/*`, use it.
3. Else find the most recent RC on origin:

```bash
RC_BRANCH=$(git ls-remote --sort=-version:refname origin "rc/*" \
  | head -1 \
  | awk '{print $2}' \
  | sed 's|refs/heads/||')
```

If no RC branch is found at this point, abort with an error.

### 2. Runtime staging detection

```bash
git ls-remote --exit-code origin staging &>/dev/null || {
  echo "No staging branch on origin — skipping."
  exit 0
}
```

This is a graceful no-op, not an error. Repos without a staging branch use `rc → main` directly.

### 3. Force-reset staging to the RC

```bash
git push origin "$RC_BRANCH":staging --force
```

### 4. Report

Output:
- RC branch used (e.g. `rc/2026-04-16.1`)
- Confirmation that `origin/staging` now points to that RC

## Constraints

- If `origin/staging` does not exist, exit 0 silently — never treat it as an error
- Never force-push any branch other than `staging`
- Never modify the RC branch itself
