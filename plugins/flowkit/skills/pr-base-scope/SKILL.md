---
name: pr-base-scope
description: Set or unset the claude.prBase git config key to scope the PR target branch for a session. Sub-skill used by ship and swarm loop mode.
---

# pr-base-scope

Set or unset `claude.prBase` — a local git config key that tells `/open-pr` which branch to target when creating a pull request. Used by `/ship` to pin PRs to `develop` during the ship flow, and by swarm loop mode to scope multi-PR sessions.

## Operations

### Set

Pin the PR target branch for the current session:

```bash
git config claude.prBase <branch>
```

Example — pin to develop:

```bash
git config claude.prBase develop
```

### Unset

Revert to the default target (`develop`):

```bash
git config --unset claude.prBase
```

### Read

Resolve the current target branch (used by `/open-pr`):

```bash
git config claude.prBase 2>/dev/null || echo "develop"
```

If the key is not set, this returns `develop` as the default.

## Usage by Callers

| Caller | Action |
|--------|--------|
| `/ship` | Sets `claude.prBase develop` before opening PRs, then unsets after the flow completes |
| `/swarm` loop mode | Sets `claude.prBase` to the appropriate integration branch for the loop session |
| `/open-pr` | Reads `claude.prBase` to resolve the target branch before creating the PR |

## Constraints

- This key is local to the repo — it is never committed or pushed
- Always unset after a scoped flow completes to avoid stale targeting in future sessions
