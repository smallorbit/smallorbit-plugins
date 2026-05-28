---
name: sync
description: Sync local main after a merge — pull latest, prune stale remote-tracking refs, and delete merged local branches.
triggers:
  - "/sync"
  - "sync main"
  - "sync back to main"
  - "clean up after merge"
allowed-tools: Bash
---

# sync

Return to a clean `main` state after a PR has been merged. Pulls the latest from origin, prunes stale remote-tracking refs, and removes local branches that have already been merged into `main`.

## Input

No arguments.

## Process

### 1. Switch to main and pull

Check out `main` and pull the latest from `origin` (never leave `main` stale before the prune/cleanup steps below):

```bash
git checkout main
git pull origin main
```

### 2. Prune stale remote-tracking refs

```bash
git fetch --prune
```

### 3. Delete merged local branches

List local branches fully merged into `main` (excluding `main` and the current branch), then delete them:

```bash
git branch --merged main | grep -vE '^\*|^[[:space:]]*main$' | xargs -r git branch -d
```

### 4. Report

Print a summary:

- Current HEAD (branch + latest commit)
- Any local branches deleted (or "No merged branches to clean up" if none)
