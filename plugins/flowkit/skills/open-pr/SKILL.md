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

### 0. First-run default-branch nudge

Before any other preflight, invoke the [`default-branch-prompt`](../default-branch-prompt/SKILL.md) sub-skill. It is a no-op in every case except the narrow first-run-on-`main`-default scenario:

- If `git config --get claude.flowkit.defaultBranchPrompted` is `true`, the sub-skill exits silently.
- If `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'` fails, returns empty, or returns anything other than `main`, the sub-skill exits silently.
- Only when the GitHub default branch is exactly `main` does the sub-skill surface an `AskUserQuestion` offering `Switch to develop` / `Keep main as default` / `Don't ask again`. Each definitive answer (`Switch` success, `Keep main as default`, `Don't ask again`) sets `claude.flowkit.defaultBranchPrompted=true`; `Cancel` at the second confirmation leaves the marker unset so the prompt resurfaces next time. `Switch` additionally runs `gh repo edit --default-branch develop` after a second confirmation.

This nudge is fire-and-forget — open-pr does not branch on its outcome. After the sub-skill returns, continue with step 1 regardless of which path the user took (or whether the prompt fired at all).

### 1. Check current branch

```bash
git rev-parse --abbrev-ref HEAD
```

If the current branch is `develop`, `main`, `master`, or `staging`, stop immediately and report:

> Cannot open a PR from a protected branch. Check out a feature branch first.

### 2. Determine base branch

Resolve the base branch using the following precedence order:

1. **Explicit caller arg** — if `$ARGUMENTS` contains a `--base <branch>` flag, extract and use it.
2. **`claude.flowkit.prBase`** — per-session config key (set by swarm loop / cut-epic).
3. **Legacy `claude.prBase`** — deprecated key (with migration notice).
4. **`develop` if it exists on the remote** — check with `git ls-remote`.
5. **GitHub default** — fall through to gh CLI default, but emit a one-line warning.

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

# 3. Legacy claude.prBase (deprecated)
if [ -z "$BASE" ]; then
  LEGACY=$(git config claude.prBase 2>/dev/null)
  if [ -n "$LEGACY" ]; then
    BASE="$LEGACY"
    echo "note: claude.prBase is deprecated. Migrate with:" >&2
    echo "  git config --unset claude.prBase" >&2
    echo "  git config claude.flowkit.prBase $LEGACY" >&2
  fi
fi

# 4. develop if it exists on the remote
if [ -z "$BASE" ]; then
  if git ls-remote --heads origin develop | grep -q 'refs/heads/develop'; then
    BASE="develop"
  fi
fi

# 5. Fallback — use the repo default and warn
if [ -z "$BASE" ]; then
  REPO_DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
  echo "warning: no base branch configured and 'develop' not found on remote; falling back to repo default ($REPO_DEFAULT)" >&2
  BASE="$REPO_DEFAULT"
fi
```

`$BASE` is always non-empty after step 2 — pass it explicitly as `--base "$BASE"` to `gh pr create`. This respects any scoped override set by the `pr-base-scope` sub-skill.

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

### 7. Warn when closing keywords target a non-default branch

GitHub's auto-close keywords (`Closes/Fixes/Resolves #N`) only fire when a PR merges into the repo's default branch. If the assembled body contains any closing keyword and `$BASE` is not the GitHub default, emit a one-line note pointing the user at `/flowkit:release`, which runs an explicit `gh issue close` loop after the staging→main merge:

```bash
if printf '%s\n' "$PR_BODY" | grep -qiE '(closes|fixes|resolves) #[0-9]+'; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
  if [ -n "$DEFAULT_BRANCH" ] && [ "$BASE" != "$DEFAULT_BRANCH" ]; then
    echo "note: 'Closes #N' won't fire auto-close on PRs into $BASE when default branch is $DEFAULT_BRANCH. /flowkit:release will close those issues at release time." >&2
  fi
fi
```

This is informational only — do not abort or rewrite the body. The `/release` and `/hotfix` skills explicitly close aggregated issues after their respective merges, so the lifecycle still completes.

### 8. Lint the assembled body for broken closing-keyword footers

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

### 9. Open the PR

`$BASE` is always non-empty at this point (step 2 guarantees it). Pass it explicitly:

```bash
gh pr create \
  --base "$BASE" \
  --head "$(git rev-parse --abbrev-ref HEAD)" \
  --title "<title>" \
  --body "<assembled body from step 6>"
```

### 10. Report

Output the PR URL returned by `gh pr create`.

## Constraints

- Always resolve `--base` before calling `gh pr create` using the precedence: explicit caller arg → `claude.flowkit.prBase` → legacy `claude.prBase` → `develop` (if remote exists) → repo default (with warning). `$BASE` is always non-empty; `--base "$BASE"` is always passed.
- Never target `main` directly unless `claude.flowkit.prBase` (or legacy `claude.prBase`) is explicitly set to `main`
- Never open a PR from a protected branch (`develop`, `main`, `master`, `staging`)
- If `gh` is not installed or not authenticated, report the error and stop — do not attempt workarounds
- Do not force-push; use a plain `git push -u origin HEAD`
