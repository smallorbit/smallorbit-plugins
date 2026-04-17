---
name: git-sync-develop
description: Check out develop and pull the latest from origin. Sub-skill used by sync, release, and hotfix.
---

# git-sync-develop

Check out the `develop` branch and pull the latest from `origin`.

## Process

```bash
git checkout develop
git pull origin develop
```

## Constraints

- Always pull after checkout — never leave develop at a stale commit
