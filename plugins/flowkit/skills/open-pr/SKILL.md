---
name: open-pr
description: Push the current branch and open a GitHub pull request against main (or the pinned base). Use after committing changes.
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

If the current branch is `main` or `master`, stop immediately and report:

> Cannot open a PR from a protected branch. Check out a feature branch first.

### 2. Determine base branch

Resolve `$BASE` per the canonical chain at [`plugins/_shared/base-resolution.md`](../../../_shared/base-resolution.md).

<!-- include: plugins/_shared/base-resolution.md -->

```bash
# 1. Explicit caller arg
BASE=""
if echo "$ARGUMENTS" | grep -qE '(^|[[:space:]])\-\-base[= ]'; then
  BASE=$(echo "$ARGUMENTS" | grep -oE '(^|[[:space:]])\-\-base[= ][^ ]+' | head -1 | sed 's/.*--base[= ]//')
fi

# 2. claude.flowkit.prBase config key
if [ -z "$BASE" ]; then
  BASE=$(git config claude.flowkit.prBase 2>/dev/null)
fi

# 3. Default to main
if [ -z "$BASE" ]; then
  BASE="main"
fi

# 4. Guard — resolved base must not equal current HEAD
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BASE" = "$HEAD_BRANCH" ]; then
  echo "ERROR: resolved base ($BASE) is the same as the current branch ($HEAD_BRANCH)." >&2
  echo "This usually means you're on an epic branch with claude.flowkit.prBase pinned" >&2
  echo "to itself. To open the epic's own integration PR, do one of:" >&2
  echo "  - rerun with an explicit override: /flowkit:pr --base main" >&2
  echo "  - unset the pin first: git config --unset claude.flowkit.prBase" >&2
  exit 1
fi
```

### 3. Push branch to origin

```bash
git push -u origin HEAD
```

### 4. Determine PR title

Use the first applicable source:
1. `$ARGUMENTS` if it looks like a title (short phrase)
2. The most recent commit message subject line
3. The branch name converted to title case (strip prefix, replace hyphens with spaces)

### 5. Discover issue-ref tokens from commit messages

Scan every commit on the branch (since divergence from `$BASE`) for issue-reference tokens. Match case-insensitively against `closes|fixes|refs|resolves #<number>`, but emit each match **verbatim** (preserving the author's original casing). Deduplicate while keeping first-seen order.

```bash
REFS=$(git log "origin/$BASE..HEAD" --pretty=format:'%B' \
  | grep -oiE '(closes|fixes|refs|resolves) #[0-9]+' \
  | awk '!seen[tolower($0)]++')
```

`$REFS` is a newline-delimited list of tokens (possibly empty). These are appended verbatim to the PR body footer. Do not re-derive closure rules — honor what the author wrote in the commits.

### 6. Assemble the PR body

Emit the canonical three-section body (see template below), followed by a blank line and the discovered ref tokens (if any).

- `## Summary` — 1–3 sentences derived from the diff and the commit messages on the branch. If `$ARGUMENTS` contains a longer description, use it to inform the Summary. Otherwise, synthesize from `git log "origin/$BASE..HEAD"` and `git diff "origin/$BASE..HEAD" --stat`.
- `## Changes` — bulleted list of concrete changes, one bullet per logical change (not per file). Derive from the diff and commit subjects.
- `## Test plan` — bulleted checklist (`- [ ]`) of verification steps a reviewer or CI can actually check.
- Footer — blank line, then `$REFS` verbatim, one token per line.

#### Body template

The body shape, footer grammar, and worked example live in [`plugins/_shared/pr-body.md`](../../../_shared/pr-body.md) — that is the single source of truth.

<!-- include: plugins/_shared/pr-body.md -->

**Override rule for `open-pr`**: when tokens come from commit messages on the branch, emit them **verbatim** — do not rewrite `Fixes`/`Resolves` into `Closes`. The canonical guidance applies to newly authored bodies; `open-pr` forwards what the author committed.

### 7. Lint the assembled body for broken closing-keyword footers

GitHub only parses one closing keyword per line. A footer like `Closes #1 #2 #3` silently leaves `#2` and `#3` open. Reject the body before calling `gh pr create` if any line packs multiple issue refs onto a single closing keyword:

```bash
if printf '%s\n' "$PR_BODY" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+[[:space:]]+#[0-9]+'; then
  echo "ERROR: PR body contains a space-separated closing-keyword footer (e.g. 'Closes #1 #2 #3')." >&2
  echo "GitHub only parses one closing keyword per line; the trailing refs would silently stay open." >&2
  echo "Rewrite the footer with one token per line:" >&2
  echo "  Closes #1" >&2
  echo "  Closes #2" >&2
  echo "  Closes #3" >&2
  exit 1
fi
```

Fail loudly rather than auto-rewriting — the author should see and fix the footer themselves so the same mistake does not recur in the source commits.

### 8. Open the PR

`$BASE` is always non-empty at this point (step 2 guarantees it). Pass it explicitly:

```bash
gh pr create \
  --base "$BASE" \
  --head "$(git rev-parse --abbrev-ref HEAD)" \
  --title "<title>" \
  --body "<assembled body from step 6>"
```

### 9. Report

Output the PR URL returned by `gh pr create`.

## Constraints

- If `gh` is not installed or not authenticated, report the error and stop — do not attempt workarounds
