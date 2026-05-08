---
name: pipeline-status
description: Show the full release pipeline at a glance — open PRs awaiting merge, develop awaiting cut, RCs/staging awaiting release, and the most recent tag. Replaces the narrower release-status skill.
triggers:
  - "/pipeline-status"
  - "pipeline status"
  - "what's pending"
  - "what's in flight"
  - "release pipeline"
  - "what's ready to release"
allowed-tools: Bash
---

# Pipeline Status

Report the state of the release pipeline at every stage so you know what to do next. Covers the full flow:

1. **In flight** — open PRs targeting `develop`
2. **Awaiting cut** — commits merged to `develop` but not yet in an RC
3. **Awaiting release** — RC or staging waiting to promote to `main`
4. **Released** — most recent release tag

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
# In flight — open PRs targeting develop
gh pr list --base develop --state open \
  --json number,title,author,isDraft,reviewDecision,mergeStateStatus,createdAt,url \
  --limit 50

# Awaiting cut — commits on develop but not yet on main
git log origin/main..origin/develop --oneline

# Awaiting release — RC branches
git ls-remote --heads origin "rc/*" | awk '{print $2}' | sed 's|refs/heads/||'

# Released — most recent version tag
git describe --tags --abbrev=0 2>/dev/null || echo "(no tags yet)"
```

If `STAGING_EXISTS=true`, also collect:

```bash
git log origin/main..origin/staging --oneline
git log origin/staging..origin/develop --oneline
```

### 4. Format and display

Print all four stages in pipeline order (left-to-right: in flight → awaiting cut → awaiting release → released). Always print every stage, even if empty — the empty state is itself information. Use "none" for empty sections.

For open PRs, summarize each row as:

```
#<num>  <review-status>  <merge-state>  <title>  (<author>, <age>)
```

Where `<review-status>` maps from `reviewDecision`:
- `APPROVED` → `APPROVED`
- `CHANGES_REQUESTED` → `CHANGES_REQUESTED`
- `REVIEW_REQUIRED` or null → `NEEDS_REVIEW`
- `isDraft: true` → `DRAFT` (takes precedence)

And `<merge-state>` maps from `mergeStateStatus`:
- `CLEAN` → `clean`
- `BLOCKED` / `BEHIND` → `blocked`
- `DIRTY` / `UNSTABLE` → `conflicts` / `ci-failing`
- anything else → the raw value, lowercased

**Example (staging absent, active queue):**

```
── Pipeline Status ────────────────────────────────
Released: v2026.4.19.12

[In flight] Open PRs → develop (2):
  #471  APPROVED       clean    docs(swarmkit): fix epic loop          (@alice, 2h)
  #472  DRAFT          —        feat(flowkit): release back-merge      (@bob, 30m)

[Awaiting cut] Develop → main (2 commits):
  • chore(deps): bump axios          (1h ago)
  • feat(ui): new dashboard layout   (30m ago)

[Awaiting release] RC branches: none

Next step: merge #471 (approved), then /cut
───────────────────────────────────────────────────
```

**Example (staging present, RC in flight):**

```
── Pipeline Status ────────────────────────────────
Released: v2026.4.15

[In flight] Open PRs → develop: none

[Awaiting cut] Develop → staging (2 commits):
  • chore(deps): bump axios          (1h ago)
  • feat(ui): new dashboard layout   (30m ago)

[Awaiting release] Staging → main (2 commits):
  • fix(auth): correct token expiry  (3h ago)
  • feat(api): add pagination        (2d ago)

RC branches:
  rc/2026-04-15.1  ← currently in staging

Next step: /release to ship staging → main
───────────────────────────────────────────────────
```

**Example (everything clear):**

```
── Pipeline Status ────────────────────────────────
Released: v2026.4.19.12

[In flight] Open PRs → develop: none
[Awaiting cut] Develop → main: none
[Awaiting release] RC branches: none

Next step: nothing to ship — develop is in sync with main.
───────────────────────────────────────────────────
```

### 5. Suggest next action

Priority — first matching rule wins:

| Condition | Suggestion |
|-----------|------------|
| ≥1 open PR has failing CI or merge conflicts | "Resolve blockers on #N" |
| ≥1 open PR is approved with clean merge state | "Merge #N (approved)" |
| ≥1 open PR is not yet reviewed (non-draft) | "Review open PRs: #N, #M" |
| Staging has commits | `/release` to ship staging → main |
| RC branch exists, no staging | `/release` to promote RC to main |
| Develop has commits, no RC | `/cut` to create a release candidate |
| Nothing pending anywhere | "Nothing to ship. Develop is in sync with main." |

Draft PRs never block the suggestion — they're flagged in the display but skipped in the "needs review" rule.

## Constraints

- Read-only — never mutate any branch, tag, PR, or label
- Always run `git fetch origin` first so data is current
- Always print all four pipeline stages, even empty ones, so the user sees the whole shape
- Never omit the "Next step" line — always conclude with actionable guidance
