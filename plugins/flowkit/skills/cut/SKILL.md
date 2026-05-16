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

**Refspec collision (read before pushing an RC branch anywhere else).** Once both the RC branch and the same-named tag exist locally, every subsequent `git push origin <name>` against that name is ambiguous and fails with:

```
error: src refspec rc/YYYY-MM-DD.N matches more than one
```

This affects any later RC-branch push — most notably the force-push performed by `flowkit:release` step 3 after rebasing the RC onto `origin/main`. The fix is to use the fully qualified refspec form whenever pushing the RC branch in the presence of the matching tag:

```bash
git push --force-with-lease origin "refs/heads/${RC_BRANCH}:refs/heads/${RC_BRANCH}"
```

Both pushes above (the initial `-u` push of the branch and the tag push) already use the disambiguated form for consistency, even though only one of the two names exists at the moment of the first push. Renaming the tag to a separate namespace (e.g. `rc-tag/...`) would also resolve this but is out of scope here — the documentation route is preferred because it keeps the tag/branch pairing intact and the cost is one extra refspec qualifier at each push site.

**Always brace the variable** (`${RC_BRANCH}`, not `$RC_BRANCH`) inside the refspec strings. When the snippet runs under zsh (or any shell with the `:r` parameter modifier), the unbraced form `$RC_BRANCH:refs/heads/...` is parsed as "value of `$RC_BRANCH` with trailing extension stripped, followed by the literal `efs/heads/...`" — the `:r` modifier consumes the `r` from `refs/heads/` and drops the `.N` suffix from the branch name. The resulting refspec looks like `refs/heads/rc/YYYY-MM-DDefs/heads/rc/YYYY-MM-DD.N` and fails with `src refspec ... does not match any`. Bracing the variable terminates the parameter name before the `:`, so the modifier path is never taken. Bash 5.x does not implement `:r` and ignores the problem; zsh does and silently mangles the string.

### 4. Report

Output:
- RC branch name created (e.g. `rc/2026-04-16.1`)

## Constraints

- Always cut from `origin/develop`, never from a local branch
- RC branch naming must follow `rc/YYYY-MM-DD.N` exactly (N starts at 1)
- Never push to any branch other than the new RC branch in this skill
