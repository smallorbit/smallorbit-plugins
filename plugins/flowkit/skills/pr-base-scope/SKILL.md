---
name: pr-base-scope
description: Set or unset the claude.flowkit.prBase git config key to scope the PR target branch for a session. Sub-skill used by ship and swarm loop mode.
---

# pr-base-scope

Set or unset `claude.flowkit.prBase` — a local git config key that tells `/open-pr` which branch to target when creating a pull request. Used by `/ship` to pin PRs to `develop` during the ship flow, and by swarm loop mode to scope multi-PR sessions.

The legacy key `claude.prBase` is still read as a fallback for backward compatibility, but is never written. When read, it emits a one-line deprecation notice pointing at the migration commands.

## Operations

### Set

Pin the PR target branch for the current session:

```bash
git config claude.flowkit.prBase <branch>
```

Example — pin to develop:

```bash
git config claude.flowkit.prBase develop
```

### Unset

Revert to the default target (`develop`):

```bash
git config --unset claude.flowkit.prBase
```

### Read

Resolution order (authoritative spec in [`open-pr/SKILL.md`](../open-pr/SKILL.md) step 2):

1. `--base <branch>` in `$ARGUMENTS`
2. `claude.flowkit.prBase`
3. `claude.prBase` — legacy fallback (emits deprecation notice)
4. `develop` if it exists on the remote
5. Repo default branch via `gh repo view` (with warning)

`$BASE` is always non-empty after resolution.

## Constraints

- This key is local to the repo — it is never committed or pushed
- Always unset after a scoped flow completes to avoid stale targeting in future sessions
- Never write to the legacy `claude.prBase` key. All set/unset operations target `claude.flowkit.prBase` only
- The legacy fallback is a soft deprecation — keep it indefinitely
