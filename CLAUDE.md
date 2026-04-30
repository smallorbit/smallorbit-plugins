# smallorbit-plugins

Monorepo hosting Claude Code plugins. See the [repo README](./README.md#available-plugins) for the current plugin catalog — it's the canonical source and stays in sync as plugins ship.

## User-Facing Docs

The root [README](./README.md) owns two canonical anchors that other surfaces cross-link to rather than duplicate:

- `#available-plugins` — plugin catalog.
- `#getting-started` — end-to-end walkthrough for new users (prereqs → install → `/spec` → `/swarm` → ship).

The landing page (`docs/index.html`) and each plugin README link back to these anchors instead of carrying parallel copies. When updating onboarding narrative, edit the root README and let the teasers point to it — don't fork the walkthrough into individual plugin READMEs.

## Release Process

Before every release, run `/bump-versions` to increment `plugin.json` versions for any plugins that have changed. This is required — without a version bump, existing users' clients won't pick up the updated code.

The bump-versions skill handles:
1. Detecting which plugins have changed since their last per-plugin tag
2. Asking for semver bump type (patch / minor / major) per plugin
3. Updating each `plugin.json`
4. Creating per-plugin git tags (`{plugin-name}--v{version}`)

Run it before staging and committing the release.

## Plugins

`swarmkit` includes an experimental skill marked with the `x-` prefix:

- `x-swarm` — variant of `/swarm` that collapses preflight, gather, verify, and teardown into shell scripts to reduce model round-trips.

The `x-` prefix is the convention for experimental skills in this plugin. See `plugins/swarmkit/README.md` for details.

`squadkit` is the interactive multi-role collaboration plugin (sibling to swarmkit's parallel-issue resolution). It introduces the `roles → squads → crews` vocabulary and ships `spawn-team`, `init`, and a `SessionStart` hook that re-asserts role context on resume.

**Crew shapes.** Crew profiles carry an optional `kind:` field — `execution` (default) for crews that ship code, `discovery` for read-only research crews that produce blueprint comments on GitHub issues instead of PRs. Discovery crews skip worktree provisioning, epic-branch cutting, and `claude.flowkit.prBase` pinning. See [`plugins/squadkit/docs/patterns/discovery-coordination.md`](./plugins/squadkit/docs/patterns/discovery-coordination.md) for the architect-led coordination pattern.

**Base-branch convention.** Execution crews always work on a `feature/<slug>-<issue>` branch cut from `develop`, owned by `spawn-team`. They never commit directly to `develop`. Discovery crews stay on `develop` since they don't produce code. The supporting flow primitives live in flowkit:

- `flowkit:cut-epic` — cut the long-lived feature branch standalone (equivalent to the inline cut performed by `spawn-team --epic`).
- `flowkit:preview-epic` — preview the combined epic-to-base diff before opening the final integration PR.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.

**PR body standard**: All PRs opened by agents in this repo must follow the canonical three-section shape (`## Summary`, `## Changes`, `## Test plan`) plus an issue-reference footer. The spec lives at [`plugins/_shared/pr-body.md`](./plugins/_shared/pr-body.md) — reference it instead of inventing a local format.
