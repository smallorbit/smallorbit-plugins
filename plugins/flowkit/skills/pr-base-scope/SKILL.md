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

Resolve the current target branch (used by `/open-pr`). Apply this resolution order:

1. `claude.flowkit.prBase` — primary source of truth
2. `claude.prBase` — legacy fallback (emits deprecation notice when hit)
3. Built-in default: `develop`

```bash
BASE=$(git config claude.flowkit.prBase 2>/dev/null)
if [ -z "$BASE" ]; then
  LEGACY=$(git config claude.prBase 2>/dev/null)
  if [ -n "$LEGACY" ]; then
    BASE="$LEGACY"
    echo "note: claude.prBase is deprecated. Migrate with:" >&2
    echo "  git config --unset claude.prBase" >&2
    echo "  git config claude.flowkit.prBase $LEGACY" >&2
  else
    BASE="develop"
  fi
fi
```

## Usage by Callers

| Caller | Action |
|--------|--------|
| `/ship` | Sets `claude.flowkit.prBase develop` before opening PRs, then unsets after the flow completes |
| `/swarm` loop mode | Sets `claude.flowkit.prBase` to the appropriate integration branch for the loop session |
| `/cut-epic` | Sets `claude.flowkit.prBase` to the long-lived epic branch so sub-PRs target it; user runs **Unset** when the epic ships |
| `/open-pr` | Reads the resolved base (new key → legacy key → `develop`) before creating the PR |

## Constraints

- This key is local to the repo — it is never committed or pushed
- Always unset after a scoped flow completes to avoid stale targeting in future sessions
- Never write to the legacy `claude.prBase` key. All set/unset operations target `claude.flowkit.prBase` only
- The legacy fallback is a soft deprecation — keep it indefinitely
