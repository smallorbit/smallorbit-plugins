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

### 3. Present the catalog for approval

Show the user a summary table before creating anything:

```
| # | Title | Category | Priority | Labels |
|---|-------|----------|----------|--------|
| 1 | ...   | bug      | high     | bug, priority:high |
| 2 | ...   | refactor | medium   | refactor, priority:medium |
```

If `--auto` was passed in `$ARGUMENTS`, skip the approval step and proceed directly to issue creation.

Otherwise, wait for user approval. The user may ask to:
- Remove findings they don't want filed
- Adjust priorities
- Change titles or descriptions
- Add additional context

### 4. Create issues

After approval, create all issues via `gh issue create`:
- Apply the labels from the table
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
