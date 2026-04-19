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

**In a single assistant turn**, emit (a) the preview above and (b) an `AskUserQuestion` call. Never end the turn after the preview without the tool call.

**Wrong shape** (never do this):

```
Title: Harden approval gates
Labels: enhancement, priority:medium
---
## Problem ...
Let me know if you'd like changes.
← turn ends; silent wait
```

**Right shape** (always do this):

```
Title: Harden approval gates
Labels: enhancement, priority:medium
---
## Problem ...
← immediately followed by AskUserQuestion in the same turn:
AskUserQuestion("File this issue?", ["File as shown", "Adjust title / labels / body", "Cancel"])
```

**Pre-end self-check**: Before ending the turn in step 4, verify that the last action is an `AskUserQuestion` call. If the preview was shown but no tool call was made, emit the call immediately.

If the user selects an adjust or cancel option, loop back (update the draft or abort) before re-asking.

### 5. Ensure labels exist

Check `gh label list` and create any missing labels (type + priority) before filing.

### 6. Create the issue

```bash
gh issue create --repo <repo> --title "<title>" --label "<labels>" --body "<body>"
```

### 7. Report

Output the created issue URL.

## Constraints

- The draft preview and the `AskUserQuestion` approval call must be emitted in the **same assistant turn** — showing the preview and ending the turn without calling `AskUserQuestion` is a defect, even if a prose invitation is included.
- Never create the issue without showing the preview first
- Never skip the duplicate check
- Keep body concise — problem + impact + fix only
- Match the label style already in the repo
- Never write `#<number>` tokens in the issue body unless you intend a real cross-reference to that exact issue — GitHub auto-links them, so a stray `#3` will silently link to unrelated issue 3 in the repo. Strip or rewrite any such token inherited from `$ARGUMENTS` before filing (use "task 3" or "issue 3" without the hash).
