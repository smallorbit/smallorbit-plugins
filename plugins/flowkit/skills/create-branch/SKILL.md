---
name: create-branch
description: Create a new git branch off of `develop` for the following work. Use when starting a new feature, fix, or task.
triggers:
  - "/create-branch"
  - "create a branch"
  - "create branch"
  - "new branch"
allowed-tools: Bash
---

# Create Branch

Create a new git branch off of `origin/develop` and check it out locally.

## Input

`$ARGUMENTS` — desired branch name or a description of the work. If a full branch name is provided, use it as-is (after validating it). If a description is provided, infer a branch name from it.

## Process

### 1. Fetch latest remote state

```bash
git fetch origin
```

### 2. Determine branch name

If `$ARGUMENTS` is provided:
- If it looks like a branch name (kebab-case, already has a prefix), use it directly.
- If it looks like a description (plain English), infer a branch name:
  - Choose a prefix based on intent: `feat/`, `fix/`, `chore/`, or `docs/`
  - Convert the description to kebab-case
  - Keep the full name at 50 characters or fewer
  - Examples: "add user auth" → `feat/add-user-auth`, "fix login timeout" → `fix/login-timeout`

If `$ARGUMENTS` is omitted, infer the branch name from recent todos, open issues, or conversation context using the same rules above.

### 3. Validate branch name

Reject the following names outright — do not create them:
- `main`
- `master`
- `develop`
- `staging`

If the inferred or provided name matches one of these, stop and ask the user for a different name.

### 4. Create and checkout the branch

```bash
git checkout -b <name> origin/develop
```

### 5. Confirm

Report the branch name that was created, e.g.:

> Branch `feat/add-user-auth` created from `origin/develop`.

## Constraints

- Always branch from `origin/develop`, never from a local `develop` (which may be behind)
- If unable to infer a branch name and `$ARGUMENTS` is empty, ask the user what the branch is for
