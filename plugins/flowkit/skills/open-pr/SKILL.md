---
name: open-pr
description: Push the current branch and open a GitHub pull request. Use after committing changes to merge work into develop.
triggers:
  - "/open-pr"
  - "open a PR"
  - "push and open PR"
  - "create PR"
  - "open pull request"
allowed-tools: Bash
---

# Open PR

Push the current branch to origin and open a GitHub pull request against the base branch.

## Input

`$ARGUMENTS` — optional PR title or description hints. If provided, use this to inform the PR title and body. If omitted, derive the title from the branch name or most recent commit message.

## Process

### 1. Check current branch

```bash
git rev-parse --abbrev-ref HEAD
```

If the current branch is `develop`, `main`, `master`, or `staging`, stop immediately and report:

> Cannot open a PR from a protected branch. Check out a feature branch first.

### 2. Determine base branch

Resolve the base branch using the `pr-base-scope` read order: new key → legacy key (with deprecation notice) → `develop` default.

```bash
BASE=$(git config claude.flowkit.prBase 2>/dev/null)
if [ -z "$BASE" ]; then
  LEGACY=$(git config claude.prBase 2>/dev/null)
  if [ -n "$LEGACY" ]; then
    BASE="$LEGACY"
    echo "note: claude.prBase is deprecated. Migrate with:" >&2
    echo "  git config --unset claude.prBase" >&2
    echo "  git config claude.flowkit.prBase $LEGACY" >&2
  else
    BASE="develop"
  fi
fi
```

Use `$BASE` as the PR target. This respects any scoped override set by the `pr-base-scope` sub-skill.

### 3. Push branch to origin

```bash
git push -u origin HEAD
```

### 4. Determine PR title

Use the first applicable source:
1. `$ARGUMENTS` if it looks like a title (short phrase)
2. The most recent commit message subject line
3. The branch name converted to title case (strip prefix, replace hyphens with spaces)

### 5. Determine PR body

Use the first applicable source:
1. `$ARGUMENTS` if it contains a longer description
2. The full body of the most recent commit message
3. A minimal placeholder referencing the branch

### 6. Open the PR

```bash
gh pr create \
  --base "$BASE" \
  --head "$(git rev-parse --abbrev-ref HEAD)" \
  --title "<title>" \
  --body "<body>"
```

### 7. Report

Output the PR URL returned by `gh pr create`.

## Constraints

- Never target `main` directly unless `claude.flowkit.prBase` (or legacy `claude.prBase`) is explicitly set to `main`
- Never open a PR from a protected branch (`develop`, `main`, `master`, `staging`)
- If `gh` is not installed or not authenticated, report the error and stop — do not attempt workarounds
- Do not force-push; use a plain `git push -u origin HEAD`
