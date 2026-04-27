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

<!-- include: plugins/_shared/pr-body.md -->

The canonical spec is duplicated inline below until publish-time include expansion lands. When that infrastructure ships, only the include marker above remains and this block is removed.

> # Canonical PR Body Specification
>
> Every PR opened by plugins in this repo uses the shape defined here. This is the single source of truth — skills that emit PR bodies reference this document rather than carrying their own copy.
>
> ## Body shape
>
> A PR body has three sections in this order, followed by a footer of issue-reference tokens.
>
> ### `## Summary`
>
> 1–3 sentences derived from the diff and the commit messages on the branch. State what the change does and why. No bullets. No file paths. No restating the title.
>
> ### `## Changes`
>
> Bulleted list of concrete changes, each with a file reference where applicable. One bullet per logical change, not per file. Group related edits. Keep bullets tight — a reviewer should be able to scan the list and predict the diff.
>
> ### `## Test plan`
>
> Bulleted checklist (`- [ ]`) of verification steps. Each item is something a reviewer or CI can actually check. Prefer behavioral checks ("PR body renders with all three sections") over implementation checks ("function returns correct value"). If the change is pure docs or config, the checklist may be short — but it must exist.
>
> ## Issue-reference footer
>
> After the three sections, emit a blank line, then one token per line using GitHub's closing-keyword grammar.
>
> | Token | When to use |
> |-------|-------------|
> | `Closes #N` | The child issue `#N` is fully resolved by this PR. GitHub will auto-close it on merge to the default branch. |
> | `Refs #N` | The parent epic `#N`, or any issue this PR only partially advances. Does not auto-close. |
>
> > **Important:** GitHub only parses one closing keyword per line. `Closes #A #B #C` on a single line silently leaves `#B` and `#C` open — only `#A` is treated as a closing reference. Always emit one token per line (`Closes #A` / `Closes #B` / `Closes #C`).
>
> Rules:
>
> - Emit one `Closes #N` line per fully-resolved child issue.
> - Emit one `Refs #N` line for the parent epic, if any.
> - Emit additional `Refs #N` lines for partial-progress references (PR advances the issue but does not close it).
> - Do not use `Fixes` or `Resolves` in newly authored bodies — they are accepted by downstream aggregators for back-compat but `Closes` is canonical here.

**Override rule for `open-pr`**: when tokens come from commit messages on the branch, emit them **verbatim** — do not rewrite `Fixes`/`Resolves` into `Closes`. The canonical guidance above applies to newly authored bodies; `open-pr` forwards what the author committed.

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

- Never target `main` directly unless `claude.flowkit.prBase` (or legacy `claude.prBase`) is explicitly set to `main`
- Never open a PR from a protected branch (`develop`, `main`, `master`, `staging`)
- If `gh` is not installed or not authenticated, report the error and stop — do not attempt workarounds
- Do not force-push; use a plain `git push -u origin HEAD`
