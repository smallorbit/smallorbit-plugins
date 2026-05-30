---
name: pipeline-status
description: Show the release pipeline at a glance — open PRs targeting main awaiting merge, and the most recent release tag. Collapsed v4 surface — no RC, no awaiting-cut stage.
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

Report the state of the release pipeline so you know what to do next. Under GitHub Flow there are only two stages:

1. **In flight** — open PRs targeting `main`
2. **Released** — most recent `v*` tag

There is no awaiting-cut stage (no `develop`/`main` split) and no awaiting-release stage (no RC branches). Every PR squash-merges directly to `main`; releases are tags on `main`.

## Process

### 1. Fetch latest remote state

```bash
git fetch origin
```

### 2. Collect pipeline data

```bash
# In flight — open PRs targeting main
gh pr list --base main --state open \
  --json number,title,author,isDraft,reviewDecision,mergeStateStatus,createdAt,url \
  --limit 50

# Released — most recent v* tag (commits since it on main = unreleased)
# grep -v '--v' excludes per-plugin tags (e.g. vaultkit--v1.1.8) that otherwise leak into the v* glob
LAST_TAG=$(git tag --list 'v*' | grep -v -- '--v' | sort -V | tail -1)
if [ -n "$LAST_TAG" ]; then
  UNRELEASED=$(git log "$LAST_TAG"..origin/main --oneline | wc -l | tr -d ' ')
else
  UNRELEASED=$(git log origin/main --oneline | wc -l | tr -d ' ')
fi
```

### 3. Format and display

Print both stages in pipeline order (in flight → released). Always print every stage, even if empty — the empty state is itself information. Use "none" for empty sections.

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

**Example (active queue):**

```
── Pipeline Status ────────────────────────────────
Released: v4.0.0   (3 commits on main since)

[In flight] Open PRs → main (2):
  #471  APPROVED       clean    docs(swarmkit): fix epic loop          (@alice, 2h)
  #472  DRAFT          —        feat(flowkit): new ship flag           (@bob, 30m)

Next step: merge #471 (approved); commits on main since v4.0.0 — run /flowkit:ship when ready
───────────────────────────────────────────────────
```

### 4. Suggest next action

Priority — first matching rule wins:

| Condition | Suggestion |
|-----------|------------|
| ≥1 open PR has failing CI or merge conflicts | "Resolve blockers on #N" |
| ≥1 open PR is approved with clean merge state | "Merge #N (approved)" |
| ≥1 open PR is not yet reviewed (non-draft) | "Review open PRs: #N, #M" |
| Commits on `main` since last `v*` tag | "Run `/flowkit:ship` to tag and release" |
| Nothing pending anywhere | "Nothing to ship" |

Draft PRs never block the suggestion — they're flagged in the display but skipped in the "needs review" rule.
