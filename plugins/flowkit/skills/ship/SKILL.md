---
name: ship
description: Repo-level skill that merges all open swarm PRs, cuts a release candidate, and promotes to main. Run this after a swarm to merge everything in one shot.
triggers:
  - "/ship"
  - "ship everything"
  - "merge stack and release"
  - "ship after swarm"
allowed-tools: Bash
---

# Ship

Merge a completed swarm run in one shot: merge all open swarm PRs into develop, cut a release candidate, and promote it to main.

## Input

`$ARGUMENTS` — optional notes passed through to `/release` as release context. If omitted, everything is auto-derived.

## Process

### 1. Merge open swarm PRs

Follow `swarmkit:merge-stack`.

- If no `worktree-agent-*` PRs are open, `merge-stack` will report "No open swarm PRs found" and stop gracefully — continue to step 2.
- If any merge fails with a conflict, stop immediately and report which PR is blocked. Do not proceed to cut or release until conflicts are resolved.

### 2. Cut a release candidate

Follow `flowkit:cut` to create an `rc/YYYY-MM-DD.N` branch from `origin/develop`.

### 3. Release

Follow `flowkit:release` to merge the RC to `main`, create the version tag, close referenced issues, and clean up RC branches.

Pass `$ARGUMENTS` as the argument if provided.

### 4. Report

Summarize what happened:

- How many swarm PRs were merged (or that the step was skipped)
- Which RC was created
- Which tag was created on main
- Which issues were closed

## Constraints

- If `merge-stack` encounters a conflict, stop — do not cut or release with unresolved conflicts
- Never commit directly to `develop` or `main`
- No branch/commit/PR creation — those belong to `/pr` and `/swarm`
- If any step fails, stop immediately and report what failed and why
