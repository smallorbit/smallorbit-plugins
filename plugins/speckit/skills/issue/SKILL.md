---
name: issue
description: Quickly draft and file a single GitHub issue from a description. Checks for duplicates, previews before creating, and ensures labels exist.
triggers:
  - "/issue"
  - "file an issue"
  - "create an issue"
  - "open an issue"
  - "log this as an issue"
argument-hint: <description>
allowed-tools: Bash
---

# Issue

Quickly draft and file a single GitHub issue. The lightweight path when you know exactly what you want to file and don't need a full `/spec` interview.

## Input

`$ARGUMENTS` — a freeform description of the issue. If empty, ask the user what the issue is about before proceeding.

## Process

### 1. Detect repo

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If not in a git repo, ask the user which repo to file against.

### 2. Draft the issue

From `$ARGUMENTS`, derive:
- **Title**: short, specific, under 70 characters
- **Type**: bug | enhancement | refactor | documentation | hygiene
- **Priority**: high | medium | low (infer from the description; default to medium)
- **Body**:
  - `## Problem` — what's wrong or missing
  - `## Why this matters` — impact
  - `## Suggested fix` — concrete next steps (omit if unknown)

### 3. Check for duplicates

```bash
gh issue list --repo <repo> --state open --limit 50 --json number,title
```

If a similar issue exists, flag it and ask whether to proceed with a new one.

### 4. Preview for approval

Show the draft before creating:

```
Title:    <title>
Labels:   <type>, priority:<level>
---
<body>
```

Wait for approval. The user may adjust the title, priority, or body before proceeding.

### 5. Ensure labels exist

Check `gh label list` and create any missing labels (type + priority) before filing.

### 6. Create the issue

```bash
gh issue create --repo <repo> --title "<title>" --label "<labels>" --body "<body>"
```

### 7. Report

Output the created issue URL.

## Constraints

- Never create the issue without showing the preview first
- Never skip the duplicate check
- Keep body concise — problem + impact + fix only
- Match the label style already in the repo
- Never write `#<number>` tokens in the issue body unless you intend a real cross-reference to that exact issue — GitHub auto-links them, so a stray `#3` will silently link to unrelated issue 3 in the repo. Strip or rewrite any such token inherited from `$ARGUMENTS` before filing (use "task 3" or "issue 3" without the hash).
