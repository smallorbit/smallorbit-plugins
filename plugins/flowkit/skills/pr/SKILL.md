---
name: pr
description: Wrap up existing changes and open a pull request. Commits any uncommitted workspace changes, then pushes the current branch and opens a PR against main (or the pinned base).
triggers:
  - "/pr"
  - "create a PR for this"
  - "open a pull request for"
  - "wrap this up as a PR"
allowed-tools: Bash
---

# PR

One-shot orchestrator that takes uncommitted workspace changes all the way to an open pull request. Under GitHub Flow with squash-merge, the common case is: operator creates a branch inline, makes changes, runs `/pr`. Branch creation is the operator's responsibility — flowkit no longer ships a `/create-branch` skill.

## Input

`$ARGUMENTS` — description of the work. Used to inform the commit message and PR title/body. If omitted, each sub-skill infers from context (staged diff, branch name, commit log).

## Process

### 0. Preflight migration check

If the repository is set up for the legacy v3 develop/RC/main flow, refuse to run and direct the operator at `/flowkit:migrate-v4`:

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
DEVELOP_EXISTS=$(git ls-remote --heads origin develop | grep -c 'refs/heads/develop' || true)
MAIN_EXISTS=$(git ls-remote --heads origin main | grep -c 'refs/heads/main' || true)

if [ "$DEFAULT_BRANCH" = "develop" ] || { [ "$DEVELOP_EXISTS" -gt 0 ] && [ "$MAIN_EXISTS" -eq 0 ]; }; then
  echo "This repo is set up for flowkit v3 (develop/main split). Run \`/flowkit:migrate-v4\` to migrate to single-trunk before using v4 skills." >&2
  exit 1
fi
```

### 1. Check current branch

```bash
git rev-parse --abbrev-ref HEAD
```

If the current branch is `main` or `master`, stop and report:

> Cannot open a PR from a protected branch. Check out a feature branch first (e.g. `git checkout -b <name>`).

Branch creation is no longer part of `/pr`. The operator creates the branch inline — `/pr` only commits and opens.

### 2. Commit changes

Follow `/commit` with `$ARGUMENTS` to stage and commit all current workspace changes using conventional commits. The commit sub-skill derives the type, scope, and subject from the staged diff — no operator interview.

If the workspace is already clean (nothing to commit), skip this step.

### 3. Open PR

Follow `/open-pr` with `$ARGUMENTS` to push the branch and open a GitHub pull request against the resolved base (`--base` arg → `claude.flowkit.prBase` → `main`).

### 4. Report

Output the PR URL.

If any step fails, stop and report the error — do not continue to the next step.
