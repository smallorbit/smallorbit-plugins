---
name: ship-plugins
description: Project-local skill that chains merge-stack → bump-versions → flowkit:ship for this plugin monorepo on flowkit v4. Reentrant — each stage gracefully skips if there's nothing to do, so an interrupted run can be resumed by re-invoking.
triggers:
  - "/ship-plugins"
  - "ship plugins"
---

# Ship Plugins

Project-local wrapper that combines `swarmkit:merge-stack`, the repo-local `/bump-versions` skill, and `flowkit:ship` into one reentrant command for flowkit v4 (single-trunk main).

Lives in `.claude/skills/` because this chain only makes sense for this monorepo — `/bump-versions` is project-specific and wouldn't apply to other repos that use flowkit. Don't generalize it into flowkit.

## When to use

- After a swarm: merge the stack, bump affected plugins, ship to main
- After merging PRs manually: catch up the bump / ship tail
- To resume an interrupted run: re-invoke and each stage detects whether its work is done

## Reentrancy contract

Every stage performs a precondition check. If the check says "nothing to do", the stage announces a skip and the chain continues. No stage errors on an empty input.

Two things never happen:

1. `/bump-versions` is never run when main is in sync with origin/main and there's no epic in flight — there's nothing to ship.
2. `flowkit:ship` is never run when main is in sync with origin/main and there's no epic in flight — there's nothing to ship.

## Process

### Stage 1 — Merge open swarm PRs

Check:

```bash
OPEN_SWARM=$(gh pr list --base main --state open \
  --json headRefName --limit 100 \
  | jq '[.[] | select(.headRefName | startswith("worktree-agent-"))] | length')
```

- If `OPEN_SWARM > 0`: follow `swarmkit:merge-stack`.
- Else: announce `"Stage 1 skipped: no open swarm PRs"` and continue.

### Stage 2 — Early-exit guard: nothing to ship

Resolve whether there's work to ship (this is an optimization — Stage 3 will recompute changed plugins):

```bash
# Check if there are any changed plugins since their last per-plugin tag
CHANGED_PLUGINS=()
for P in $(ls plugins); do
  [ -f "plugins/${P}/.claude-plugin/plugin.json" ] || continue
  TAG=$(git tag --list "${P}--v*" | sort -V | tail -1)
  if [ -z "$TAG" ]; then
    CHANGED_PLUGINS+=("$P")
    continue
  fi
  COUNT=$(git log "${TAG}..origin/main" --oneline -- "plugins/${P}/" | wc -l | tr -d ' ')
  [ "$COUNT" != "0" ] && CHANGED_PLUGINS+=("$P")
done

# Check if there's an epic in flight
EPIC_BRANCH=""
PINNED=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
if [[ -n "$PINNED" && "$PINNED" =~ ^feature/ ]]; then
  EPIC_BRANCH="$PINNED"
fi
if [[ -z "$EPIC_BRANCH" ]]; then
  CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ "$CURRENT" =~ ^feature/ ]]; then
    EPIC_BRANCH="$CURRENT"
  fi
fi
```

- If no plugins have changed AND `$EPIC_BRANCH` is empty: announce `"Stage 2 skipped: no changed plugins and no epic in flight — nothing to ship"` and **stop the chain**.
- Else: continue to Stage 3.

### Stage 3 — Bump plugin versions

Check whether any plugin has commits on `origin/main` since its most recent per-plugin tag. Only consider plugins that have an existing tag or no tag yet:

```bash
CHANGED_PLUGINS=()
for P in $(ls plugins); do
  [ -f "plugins/${P}/.claude-plugin/plugin.json" ] || continue
  TAG=$(git tag --list "${P}--v*" | sort -V | tail -1)
  if [ -z "$TAG" ]; then
    CHANGED_PLUGINS+=("$P")
    continue
  fi
  COUNT=$(git log "${TAG}..origin/main" --oneline -- "plugins/${P}/" | wc -l | tr -d ' ')
  [ "$COUNT" != "0" ] && CHANGED_PLUGINS+=("$P")
done
```

- If `CHANGED_PLUGINS` is non-empty: follow `/bump-versions` (project-local skill).
- Else: announce `"Stage 3 skipped: no plugin changes since last per-plugin tags"` and continue.

### Stage 3.5 — Ship epic (conditional)

Resolve `$EPIC_BRANCH` using the same two-signal logic as `flowkit:ship`:

```bash
EPIC_BRANCH=""
PINNED=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
if [[ -n "$PINNED" && "$PINNED" =~ ^feature/ ]]; then
  EPIC_BRANCH="$PINNED"
fi
if [[ -z "$EPIC_BRANCH" ]]; then
  CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ "$CURRENT" =~ ^feature/ ]]; then
    EPIC_BRANCH="$CURRENT"
  fi
fi
```

- If `$EPIC_BRANCH` is non-empty: follow `flowkit:ship-epic`.
- Else: announce `"Stage 3.5 skipped: no epic in flight"` and continue.

### Stage 4 — Ship

Follow `flowkit:ship` to tag HEAD of main, push the tag, and create a GitHub Release.

### Stage 5 — Report

Print a per-stage summary. Use `—` for skipped stages:

```
── Ship Plugins ───────────────────────────────────
1.   merge-stack     : merged 3 PRs (#471 #472 #473)
2.   early-exit      : —
3.   bump-versions   : sessionkit 1.10.0→1.11.0, speckit 1.7.2→1.7.3
3.5  ship-epic       : feature/simplify-handoff-pickup-1019 shipped
4.   ship            : v2026.5.30.1 (closed #471 #472 #473)
───────────────────────────────────────────────────
```

Include a one-line reason for every skipped stage so the user can reason about why a given run was a no-op.

## Constraints

- Never run `/bump-versions` when main is in sync with origin/main and there's no epic in flight
- Never run the full chain when main is in sync with origin/main and there's no epic in flight — stop early at Stage 2
- Always continue past a stage with nothing to do; never error on "empty input"
- Always print a final report listing every stage and its outcome (ran / skipped + reason)
- Project-scoped: this skill is specific to `smallorbit-plugins`. Do not move it into flowkit — other flowkit consumers don't have `/bump-versions`
