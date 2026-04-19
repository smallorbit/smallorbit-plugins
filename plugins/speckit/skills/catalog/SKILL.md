---
name: catalog
description: Convert code review findings or assessment results into prioritized, labeled GitHub issues. Supports explicit input, conversation context, or file paths.
---

# Catalog Skill

Convert findings into prioritized, labeled GitHub issues: $ARGUMENTS

## Input

Accept findings from any of these sources (check in order):

1. **Explicit input** in `$ARGUMENTS` (e.g., a pasted list, a file path)
2. **Earlier in this conversation** — look for structured findings from code review or any assessment that produced categorized results
3. **A file** — if `$ARGUMENTS` is a path, read it and extract findings

If no findings are available, ask the user what to catalog.

### Tokens in `$ARGUMENTS`

Before extracting findings, scan `$ARGUMENTS` for these optional leading tokens and strip them from the findings text:

- `--auto` — skip the approval step in step 3 (see below).
- `--epic <slug>` — associate the catalogued issues with an epic identified by `<slug>`. The slug drives the epic-label logic in step 2 (ensure `epic:<slug>` exists) and step 4 (apply `epic:<slug>` to every issue in the batch). When invoked from `/speckit:spec`, the approved epic slug is passed through this same public mechanism — there is no private side channel. An optional epic title may accompany the slug (e.g. passed through from `/spec`); it is used as the label description when creating the label.

If `--epic <slug>` is **not** present, behaviour is unchanged from the no-epic flow: no epic label is applied, no warning is emitted, and the rest of the process runs exactly as documented below.

## Process

### 1. Extract findings

Parse the source into discrete findings. Each finding needs:
- **Title**: short, specific (under 70 characters)
- **Category**: bug, enhancement, refactor, documentation, hygiene
- **Severity**: high (breaks things, misleads users), medium (degrades quality), low (style, nice-to-have)
- **Body**: Problem statement, why it matters, suggested fix

### 2. Check existing labels

```bash
gh label list --repo <repo> --limit 50
```

Create any missing labels needed for the findings:
- Category labels if not present
- `priority:high`, `priority:medium`, `priority:low` if not present

Only create labels that will actually be used by the current findings.

**If an epic slug was supplied via `--epic <slug>`**, also ensure the `epic:<slug>` label exists:

- If the label is **missing**, create it with the shared epic styling:
  ```bash
  gh label create "epic:<slug>" \
    --repo <repo> \
    --color 5319E7 \
    --description "Belongs to epic: <epic title>"
  ```
  If no epic title was passed alongside the slug, fall back to a description of `Belongs to epic: <slug>`.
- If the label **already exists**, warn the user once for this batch and ask before reusing it:
  ```
  WARNING: label `epic:<slug>` already exists in this repo. Reusing it will
  apply it to every issue filed in this batch. Proceed? (y/N)
  ```
  Only continue after explicit approval. Do not silently reuse. This prompt fires at most once per catalog invocation.

If no epic slug was supplied, skip this entire block — do not list, create, or prompt for any `epic:*` label.

### 3. Present the catalog for approval

Show the user a summary table before creating anything. The `Labels` column must list every label that will be applied at creation time — including `epic:<slug>` when an epic slug is in play — so the user can confirm the full set before anything is filed:

```
| # | Title | Category | Priority | Labels |
|---|-------|----------|----------|--------|
| 1 | ...   | bug      | high     | bug, priority:high |
| 2 | ...   | refactor | medium   | refactor, priority:medium |
```

When an epic slug was supplied, the table also shows the epic label on every row and includes a single header line above the table making it explicit, e.g.:

```
Epic: epic:<slug> (applied to every issue below)

| # | Title | Category | Priority | Labels |
|---|-------|----------|----------|--------|
| 1 | ...   | bug      | high     | bug, priority:high, epic:<slug> |
| 2 | ...   | refactor | medium   | refactor, priority:medium, epic:<slug> |
```

If `--auto` was passed in `$ARGUMENTS`, skip the approval step and proceed directly to issue creation.

Otherwise, wait for user approval. The user may ask to:
- Remove findings they don't want filed
- Adjust priorities
- Change titles or descriptions
- Add additional context

### 4. Create issues

After approval, create all issues via `gh issue create`:
- Apply the labels from the table — every issue gets its category label and priority label
- **If an epic slug was supplied via `--epic <slug>`**, also pass `--label "epic:<slug>"` on every `gh issue create` invocation in the batch, alongside the category and priority labels. No issue in the batch may be created without the epic label when a slug is in play.
- If no epic slug was supplied, do not pass any `epic:*` label.
- Structure the body with:
  - `## Problem` — what's wrong
  - `## Why this matters` — impact and severity rationale
  - `## Suggested fix` — concrete next steps
- Create issues in priority order (high first)

### 5. Report

Output the created issues as a table with links:

```
| # | Issue | Priority | Labels |
|---|-------|----------|--------|
| 1 | [#N](url) title | high | ... |
```

## Constraints

- Never create issues without showing the user the catalog first (unless `--auto` was passed)
- Never create duplicate issues — check `gh issue list` for similar titles before creating
- Keep issue bodies concise — problem + impact + fix, nothing more
- Match the label style already in the repo (don't impose a new scheme)
- Never write `#<number>` tokens in issue bodies unless you intend a real cross-reference to that exact issue — GitHub auto-links them, so a token like `#3` in a body about "task 3" will link to unrelated issue 3 in the repo. When referring to sibling tasks from a plan, use "task 3" (no hash) or omit the reference entirely — task-to-task dependencies are wired by the caller (e.g. `/spec`) via the native GitHub blocked-by API, not via issue-body text.
