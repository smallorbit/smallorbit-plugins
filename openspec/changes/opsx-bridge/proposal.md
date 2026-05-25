## Why

OpenSpec's `/opsx:apply` is a single-agent task-loop runner — it walks `tasks.md` linearly in one conversation. For changes that touch multiple plugins or have parallelizable work, this is the wrong shape: we already have `/squadkit:spawn-team` (coordinated multi-role crew) and `/swarmkit:swarm-plus` (parallel isolated-worktree workers with review pass). What's missing is a bridge that lets a single OpenSpec change proposal drive either dispatcher without modifying opsx, squadkit, or swarmkit.

## What Changes

- New plugin `plugins/opsx-bridge/` with two skills:
  - `/opsx-bridge:apply-via-squad <change-name>` — reads `openspec/changes/<name>/`, derives a squad profile from the proposal/specs/tasks, invokes `/squadkit:spawn-team` with an inline brief that points at the change directory.
  - `/opsx-bridge:apply-via-swarm <change-name>` — reads `tasks.md`, files or matches GitHub issues per task (or per logical group), invokes `/swarmkit:swarm-plus` with the issue list in dependency order.
- Both skills are **additive** — they invoke existing skills (`spawn-team`, `swarm-plus`) without modifying them. No changes to opsx command files, no changes to squadkit/swarmkit skills.
- A small helper sub-skill `opsx-bridge:read-change` to parse `openspec/changes/<name>/` artifacts into the dispatcher inputs (squad profile JSON, issue list).

## Capabilities

### New Capabilities

- `opsx-bridge`: the bridge plugin's overall behavior — discovering a change directory, reading artifacts, validating apply-readiness via `openspec status`, dispatching via squadkit or swarmkit, and reconciling task completion back into `tasks.md` so `/opsx:archive` works afterward.

### Modified Capabilities

None. The bridge is purely additive — `squadkit-spawn-team` and `swarmkit` specs are unchanged. The bridge calls them as black boxes through their existing public skill surface.

## Impact

- **New plugin**: `plugins/opsx-bridge/` with `plugin.json`, two top-level skills, one sub-skill, OpenSpec spec, REFERENCES.md.
- **Marketplace metadata**: needs to be added to `marketplaces/smallorbit-plugins.json` (or equivalent) so the plugin can be installed.
- **No modifications** to opsx, squadkit, or swarmkit skills/specs.
- **GitHub issue mapping**: the swarm path needs a convention for linking `tasks.md` items to GH issues — design.md picks the approach.
- **No CI / verify changes** required — bridge invokes existing dispatchers which already have their own verify flows.
- **Dependencies**: requires `@fission-ai/openspec` CLI installed (already adopted in this repo via the prior commit).
