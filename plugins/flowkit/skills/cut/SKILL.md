---
name: cut
description: Create a release candidate branch from origin/develop.
triggers:
  - "/cut"
  - "cut a release"
  - "create release candidate"
  - "cut RC"
allowed-tools: Bash
---

# Cut

Create a versioned release candidate branch from `origin/develop`.

## Input

`$ARGUMENTS` — optional RC label or notes. If omitted, all values are auto-derived.

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

Find the highest RC **tag** number for today and increment it (tags persist after branch deletion; using max rather than count handles gaps from untagged historical RCs):

```bash
LAST_N=$(git tag --list "rc/$TODAY.*" | grep -oE '\.[0-9]+$' | tr -d '.' | sort -n | tail -1)
N=$((${LAST_N:-0} + 1))
RC_BRANCH="rc/$TODAY.$N"
```

### 3. Create and push the RC branch and tag

```bash
git checkout -b "$RC_BRANCH" origin/develop
git push -u origin "refs/heads/${RC_BRANCH}:refs/heads/${RC_BRANCH}"
git tag "$RC_BRANCH"
git push origin "refs/tags/${RC_BRANCH}"
```

The tag (`rc/YYYY-MM-DD.N`) intentionally shares the branch name. The tag is pushed immediately so future cuts count it correctly even after the branch is deleted.

**Refspec collision.** Once branch and same-named tag both exist, every `git push origin <name>` against that name fails with `error: src refspec ... matches more than one`. Both pushes above use the fully qualified form (`refs/heads/${RC_BRANCH}:refs/heads/${RC_BRANCH}`) to avoid this. Any later push of the RC branch — most notably the force-push in `flowkit:release` step 3 — must do the same.

**Always brace the variable** (`${RC_BRANCH}`, not `$RC_BRANCH`) inside refspec strings. Under zsh the unbraced form triggers the `:r` parameter modifier and silently mangles the refspec; bash 5.x doesn't have `:r` so the bug is invisible until the snippet runs under zsh.

### 4. Report

Output:
- RC branch name created (e.g. `rc/2026-04-16.1`)

## Constraints

- Never push to any branch other than the new RC branch in this skill
