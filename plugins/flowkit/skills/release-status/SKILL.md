---
name: release-status
description: Show what's in staging awaiting release and what's in develop awaiting a cut. Helps decide whether to run /cut or /release.
triggers:
  - "/release-status"
  - "release status"
  - "what's in staging"
  - "what's ready to release"
  - "check release pipeline"
allowed-tools: Bash
---

# Release Status

Report the current state of the release pipeline at a glance so you know whether to run `/cut` or `/release`.

## Process

### 1. Fetch latest remote state

```bash
git fetch origin
```

### 2. Detect staging branch at runtime

```bash
git ls-remote --exit-code origin staging &>/dev/null && STAGING_EXISTS=true || STAGING_EXISTS=false
```

### 3. Collect pipeline data

Always collect:

```bash
git log origin/main..origin/develop --oneline
git ls-remote origin "rc/*" | awk '{print $2}' | sed 's|refs/heads/||'
git describe --tags --abbrev=0 2>/dev/null || echo "(no tags yet)"
```

If `STAGING_EXISTS=true`, also collect:

```bash
git log origin/main..origin/staging --oneline
git log origin/staging..origin/develop --oneline
```

### 4. Format and display

**When `STAGING_EXISTS=true`:**

```
── Release Pipeline Status ────────────────────────
Last release: v2026.4.15

Staging (awaiting /release):
  • fix(auth): correct token expiry  (3h ago)
  • feat(api): add pagination        (2d ago)

Develop (awaiting /cut):
  • chore(deps): bump axios          (1h ago)
  • feat(ui): new dashboard layout   (30m ago)

RC branches:
  rc/2026-04-15.1  ← currently in staging

Next step: /release to ship staging → main
───────────────────────────────────────────────────
```

**When `STAGING_EXISTS=false`:**

```
── Release Pipeline Status ────────────────────────
Last release: v2026.4.15
(No staging branch detected)

Develop (awaiting /cut + /release):
  • feat(ui): new dashboard layout   (30m ago)
  • chore(deps): bump axios          (1h ago)

RC branches: none

Next step: /cut to create a release candidate
───────────────────────────────────────────────────
```

If develop has no new commits relative to main, show "Develop is up to date with main." instead of a commit list.

### 5. Suggest next action

| Condition | Suggestion |
|-----------|------------|
| Staging has commits | `/release` to ship staging → main |
| Develop has commits, no staging | `/cut` to create a release candidate |
| Nothing pending | "Nothing to ship. Develop is in sync with main." |

## Constraints

- Read-only — never mutate any branch or tag
- Always run `git fetch origin` first to ensure data is current
