---
name: sync
description: Sync local develop after a merge — pull latest, prune stale remote-tracking refs, and delete merged local branches.
triggers:
  - "/sync"
  - "sync develop"
  - "sync back to develop"
  - "clean up after merge"
allowed-tools: Bash
---

# sync

Return to a clean `develop` state after a PR has been merged. Pulls the latest from origin, prunes stale remote-tracking refs, and removes local branches that have already been merged into `develop`.

## Input

No arguments.

## Process

### 1. Switch to develop and pull

Check out `develop` and pull the latest from `origin` (never leave `develop` stale before the prune/cleanup steps below):

```bash
git checkout develop
git pull origin develop
```

### 2. Prune stale remote-tracking refs

```bash
git fetch --prune
```

### 3. Delete merged local branches

List local branches fully merged into `develop` (excluding `develop`, `main`, and the current branch), then delete them:

```bash
git branch --merged develop | grep -vE '^\*|develop|main' | xargs -r git branch -d
```

### 4. Report

Print a summary:

- Current HEAD (branch + latest commit)
- Any local branches deleted (or "No merged branches to clean up" if none)
