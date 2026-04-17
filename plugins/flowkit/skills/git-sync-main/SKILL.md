---
name: git-sync-main
description: Check out main and pull the latest from origin. Sub-skill used by release and hotfix.
---

# git-sync-main

Check out the `main` branch and pull the latest from `origin`.

## Process

```bash
git checkout main
git pull origin main
```

## Constraints

- Always pull after checkout — never leave main at a stale commit
