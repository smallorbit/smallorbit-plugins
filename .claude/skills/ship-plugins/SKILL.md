---
name: ship-plugins
description: Project-local skill that chains merge-stack → bump-versions → cut → release for this plugin monorepo. Reentrant — each stage gracefully skips if there's nothing to do, so an interrupted run can be resumed by re-invoking.
triggers:
  - "/ship-plugins"
  - "ship plugins"
---

# Ship Plugins

Project-local wrapper that combines `swarmkit:merge-stack`, the repo-local `/bump-versions` skill, and `flowkit:cut` + `flowkit:release` into one reentrant command.

Lives in `.claude/skills/` because this chain only makes sense for this monorepo — `/bump-versions` is project-specific and wouldn't apply to other repos that use flowkit. Don't generalize it into flowkit.

## When to use

- After a swarm: merge the stack, bump affected plugins, cut an RC, ship to main
- After merging PRs manually: catch up the bump / cut / release tail
- To resume an interrupted run: re-invoke and each stage detects whether its work is done

## Reentrancy contract

Every stage performs a precondition check. If the check says "nothing to do", the stage announces a skip and the chain continues. No stage errors on an empty input.

Three things never happen:

1. `/bump-versions` is never run when an RC already exists — the RC has the bumps baked in; a second bump would drift develop.
2. `/cut` is never run when develop is in sync with main and there's no existing RC.
3. `/release` is never run when there's no RC and no staging.

## Process

### Stage 1 — Merge open swarm PRs

Check:

```bash
OPEN_SWARM=$(gh pr list --base develop --state open \
  --json headRefName --limit 100 \
  | jq '[.[] | select(.headRefName | startswith("worktree-agent-"))] | length')
```

- If `OPEN_SWARM > 0`: follow `swarmkit:merge-stack`.
- Else: announce `"Stage 1 skipped: no open swarm PRs"` and continue.

### Stage 2 — Skip-ahead guard: existing RC

```bash
EXISTING_RC=$(git ls-remote --heads origin "rc/*" | head -1)
```

- If an RC exists: announce `"RC already cut — skipping bump-versions and /cut"` and jump to Stage 5.
- Else: continue to Stage 3.

### Stage 3 — Bump plugin versions

Check whether any plugin has commits on `origin/develop` since its most recent per-plugin tag. Only consider plugins that have an existing tag or no tag yet:

```bash
CHANGED_PLUGINS=()
for P in $(ls plugins); do
  [ -f "plugins/${P}/.claude-plugin/plugin.json" ] || continue
  TAG=$(git tag --list "${P}--v*" | sort -V | tail -1)
  if [ -z "$TAG" ]; then
    CHANGED_PLUGINS+=("$P")
    continue
  fi
  COUNT=$(git log "${TAG}..origin/develop" --oneline -- "plugins/${P}/" | wc -l | tr -d ' ')
  [ "$COUNT" != "0" ] && CHANGED_PLUGINS+=("$P")
done
```

- If `CHANGED_PLUGINS` is non-empty: follow `/bump-versions` (project-local skill).
- Else: announce `"Stage 3 skipped: no plugin changes since last per-plugin tags"` and continue.

### Stage 4 — Cut a release candidate

```bash
AHEAD=$(git log origin/main..origin/develop --oneline | wc -l | tr -d ' ')
```

- If `AHEAD == 0`: announce `"Stage 4 skipped: develop in sync with main — nothing to cut"` and **stop the chain** (there's nothing for Stage 5 either).
- Else: follow `flowkit:cut`.

### Stage 5 — Release

```bash
HAS_RC=$(git ls-remote --heads origin "rc/*" | head -1)
HAS_STAGING=$(git ls-remote --exit-code origin staging &>/dev/null && echo yes || echo no)
```

- If both empty: announce `"Stage 5 skipped: no RC and no staging to release"` and stop.
- Else: follow `flowkit:release`.

### Stage 6 — Report

Print a per-stage summary. Use `—` for skipped stages:

```
── Ship Plugins ───────────────────────────────────
1. merge-stack     : merged 3 PRs (#471 #472 #473)
2. rc skip-ahead   : no existing RC
3. bump-versions   : swarmkit 2.7.1→2.7.2, flowkit 2.0.4→2.1.0
4. cut             : rc/2026-04-19.15
5. release         : v2026.4.19.13 (closed #471 #472 #473)
───────────────────────────────────────────────────
```

Include a one-line reason for every skipped stage so the user can reason about why a given run was a no-op.

## Constraints

- Never run `/bump-versions` when an RC already exists on origin
- Never cut when develop is in sync with main and there is no existing RC
- Never release when there's no RC and no staging
- Always continue past a stage with nothing to do; never error on "empty input"
- Always print a final report listing every stage and its outcome (ran / skipped + reason)
- Project-scoped: this skill is specific to `smallorbit-plugins`. Do not move it into flowkit — other flowkit consumers don't have `/bump-versions`
