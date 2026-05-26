# opsx-bridge

Bridge OpenSpec changes to multi-agent dispatchers. Drive `/squadkit:spawn-team` or `/swarmkit:swarm-plus` from a single `openspec/changes/<name>/` proposal — purely additive, leaves opsx/squadkit/swarmkit untouched.

## What it does

OpenSpec's stock `/opsx:apply` is a single-agent task-loop runner: it reads `tasks.md` and walks each `- [ ]` linearly in one conversation. For changes that span multiple plugins, capabilities, or have parallelizable work, that shape is wrong. This plugin bridges the same proposal to either of two existing dispatchers:

- **`/opsx-bridge:apply-via-squad <change>`** — derive a squad profile from the proposal's `## Capabilities`, dispatch via `/squadkit:spawn-team` with `proposal.md` + `design.md` as briefs. Best for cross-capability design work coordinated under one architect.
- **`/opsx-bridge:apply-via-swarm <change>`** — group `tasks.md` by `##` section heading, map each section to a GitHub issue (reuse or file), wire dependency edges from inline `<!-- depends: -->` markers and `## Dependencies` blocks, dispatch via `/swarmkit:swarm-plus`. Best for parallel issue execution with automatic review/fix pass.

## Which dispatcher to pick

| Scenario | Pick |
|---|---|
| Change touches 2+ capabilities that need shared design state | **`apply-via-squad`** |
| Change has clear independent sections that can land as separate PRs | **`apply-via-swarm`** |
| Change is small enough to walk linearly in one conversation | `/opsx:apply` (stock — not this plugin) |
| Single capability, single section, no coordination needed | `/opsx:apply` |
| Multi-section change, ordering matters but each section is one-shot | **`apply-via-swarm`** |
| Highly interdependent code changes that benefit from cross-role review | **`apply-via-squad`** |

## Install

```bash
# Add the plugin source
/plugin marketplace add smallorbit-plugins
/plugin install opsx-bridge@smallorbit-plugins
```

Requires `@fission-ai/openspec` CLI installed globally:

```bash
npm install -g @fission-ai/openspec@latest
openspec init --tools claude   # scaffolds /opsx:* commands in your repo
```

## Quick start

```bash
# 1. Create an OpenSpec change as usual
/opsx:propose "add user authentication"

# 2. Dispatch via squad (architect + builders + reviewer + tester)
/opsx-bridge:apply-via-squad add-user-authentication

# Or dispatch via swarm (parallel agents, one per section-issue)
/opsx-bridge:apply-via-swarm add-user-authentication

# 3. After dispatcher completion, archive
/opsx:archive add-user-authentication
```

## Concepts

### Universal unit of work: OpenSpec capabilities

The bridge does not know about plugins, packages, or services. It derives parallelism from the **OpenSpec capabilities** listed in `proposal.md`'s `## Capabilities` section (New + Modified, unique). This makes the bridge portable across:

- Plugin monorepos (capability ≈ plugin)
- Multi-package workspaces (capability ≈ package)
- Single-package repos (capability ≈ logical grouping the spec author chose)
- Microservice repos (capability ≈ service)

### Base branch resolution

The bridge never hardcodes `develop`, `main`, or any specific branch. Resolution chain on every invocation:

1. `--base <branch>` flag (per-invocation override)
2. `claude.flowkit.prBase` git config (session pin)
3. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub default)

### Section-to-issue mapping (swarm path)

For the swarm path, each `##` heading in `tasks.md` becomes one GitHub issue. The bridge:

1. Slugs the section heading to a stable section-id
2. Looks for an open issue with label `opsx-change:<name>` and body marker `<!-- opsx-section: <section-id> -->`
3. Reuses the matched issue or files a new one with the section's tasks inlined
4. Wires `blocked-by` edges from two sources, merged:
   - **Inline**: `## Section B <!-- depends: section-a -->`
   - **Block**: `## Dependencies\nSection B blocked by Section A` at end of tasks.md

## Non-goals

- **Replacing `/opsx:apply`**. Stock single-agent mode remains the right choice for small linear changes.
- **Modifying squadkit or swarmkit**. The bridge calls them as black boxes through their existing public skill surface.
- **Auto-routing**. The operator picks `apply-via-squad` vs `apply-via-swarm` explicitly. The bridge does not heuristically choose.
- **Mixed-mode** (some tasks via squad, some via swarm in one change). Not supported in v1.

## Spec

The behavioral spec for this plugin lives at `openspec/specs/opsx-bridge/spec.md` (within the plugin) and is mirrored in the repo-level baseline at the root `openspec/specs/opsx-bridge/spec.md`.

## See also

- [OpenSpec](https://github.com/Fission-AI/OpenSpec) — the upstream spec-driven workflow
- `plugins/squadkit/` — multi-role coordinated dispatch
- `plugins/swarmkit/` — parallel isolated-worktree dispatch
