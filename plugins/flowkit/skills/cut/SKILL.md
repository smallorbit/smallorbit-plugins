---
name: cut
description: Create a release candidate branch from origin/develop. Detects staging at runtime and auto-stages the RC if origin/staging exists.
triggers:
  - "/cut"
  - "cut a release"
  - "create release candidate"
  - "cut RC"
allowed-tools: Bash
---

# Cut

Create a versioned release candidate branch from `origin/develop`, then automatically stage it if `origin/staging` exists.

## Input

`$ARGUMENTS` — optional RC label or notes (e.g. "hotfix notes", "skip staging"). If omitted, all values are auto-derived.

## Process

### 1. Fetch latest remote state

```bash
git fetch origin
```

### 2. Determine RC branch name

Base the name on today's date:

```bash
TODAY=$(date +%Y-%m-%d)
RC_BASE="rc/$TODAY"
```

Count existing RC **tags** for today (tags persist after branch deletion, making the increment reliable):

```bash
EXISTING=$(git tag --list "rc/$TODAY.*" | wc -l | tr -d ' ')
N=$((EXISTING + 1))
RC_BRANCH="rc/$TODAY.$N"
```

### 3. Create and push the RC branch and tag

```bash
git checkout -b "$RC_BRANCH" origin/develop
git push -u origin "$RC_BRANCH"
git tag "$RC_BRANCH"
git push origin "refs/tags/$RC_BRANCH"
```

The tag (`rc/YYYY-MM-DD.N`) shares the branch name; push it via full `refs/tags/` path to avoid the ambiguous-refspec error. The tag is pushed immediately so future cuts count it correctly even after the branch is deleted.

### 4. Runtime staging detection

```bash
git ls-remote --exit-code origin staging &>/dev/null && STAGING_EXISTS=true || STAGING_EXISTS=false
```

### 5. Auto-stage if staging exists

If `STAGING_EXISTS=true`, immediately follow the `/stage` skill with `$RC_BRANCH` as the argument.

### 6. Report

Output:
- RC branch name created (e.g. `rc/2026-04-16.1`)
- Whether `origin/staging` was detected and updated

## Constraints

- Always cut from `origin/develop`, never from a local branch
- RC branch naming must follow `rc/YYYY-MM-DD.N` exactly (N starts at 1)
- Never push to any branch other than the new RC branch in this skill
