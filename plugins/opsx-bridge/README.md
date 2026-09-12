# opsx-bridge

Bridge OpenSpec changes to multi-agent dispatchers. Drive `/squadkit:spawn-team` or `/swarmkit:swarm` from a single `openspec/changes/<name>/` proposal — purely additive, leaves opsx/squadkit/swarmkit untouched.

## What it does

OpenSpec's stock `/opsx:apply` is a single-agent task-loop runner: it reads `tasks.md` and walks each `- [ ]` linearly in one conversation. For changes that span multiple plugins, capabilities, or have parallelizable work, that shape is wrong. This plugin bridges the same proposal to either of two existing dispatchers:

- **`/opsx-bridge:apply-via-squad <change>`** — derive a squad profile from the proposal's `## Capabilities`, dispatch via `/squadkit:spawn-team` with `proposal.md` + `design.md` as briefs. Best for cross-capability design work coordinated under one architect.
- **`/opsx-bridge:apply-via-swarm <change>`** — group `tasks.md` by `##` section heading, map each section to a GitHub issue (reuse or file), merge the dependency edges from inline `<!-- depends: -->` markers and `## Dependencies` blocks and wire them as a linearized `blocked-by` chain, dispatch via `/swarmkit:swarm`. Best for parallel issue execution with automatic review/fix pass.

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

This plugin is intentionally unlisted from the `smallorbit-plugins` marketplace ([#1065](https://github.com/smallorbit/smallorbit-plugins/pull/1065)) — there is no `/plugin install opsx-bridge@smallorbit-plugins` entry. Load it directly for a session instead:

```bash
claude --plugin-dir /path/to/plugins/opsx-bridge
```

### Requirements

- `@fission-ai/openspec` CLI installed globally (both paths):

  ```bash
  npm install -g @fission-ai/openspec@latest
  openspec init --tools claude   # scaffolds /opsx:* commands in your repo
  ```

- [squadkit](../squadkit) installed — `apply-via-squad` dispatches through `squadkit:spawn-team`.
- [swarmkit](../swarmkit) installed — `apply-via-swarm` dispatches through `swarmkit:swarm`.
- An authenticated GitHub CLI (`gh`) and `jq` — both paths use them for base resolution, apply-readiness parsing, and post-completion reconciliation. The swarm path additionally files/reuses issues and wires native `blocked-by` dependencies via `gh api`.

## Quick start

```bash
# 1. Create an OpenSpec change as usual
/opsx:propose "add user authentication"

# 2. Dispatch via squad (all-rounder crew: architect, builders sized from capabilities, reviewer, tester, explorer, designer)
/opsx-bridge:apply-via-squad add-user-authentication

# Or dispatch via swarm (parallel agents, one per section-issue)
/opsx-bridge:apply-via-swarm add-user-authentication

# 3. After dispatcher completion, archive
/opsx:archive add-user-authentication
```

## Flags

| Skill | Argument | Default | Effect |
|---|---|---|---|
| both | `<change>` | required | Directory under `openspec/changes/`. |
| both | `--base <branch>` | resolved | Override the resolved base branch. See below. |
| `apply-via-squad` | `--profile <name>` | derived | Named crew profile passed through to `spawn-team`. Skips capability-based builder derivation. |
| `apply-via-squad` | `--no-epic` | epic on | Drop the `--epic` flag so the crew works against the base branch instead of a feature epic branch. |

Builders are derived as `min(unique capabilities, 4)`, defaulting to 1 when the proposal lists no capabilities, and passed to `spawn-team` as `--builders <N>` against its default `all-rounder` profile. `--no-epic` only omits `--epic` — squadkit has no such flag, so `spawn-team` still prompts for epic confirmation and the operator must answer "use base branch".

Swarm knobs (`--model`, `--worker-model`, `--reviewer-model`) are not passed through; run `/swarmkit:swarm` directly for those.

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

Step 3 is a deliberate deviation from the monorepo's canonical contract in [`plugins/_shared/base-resolution.md`](../_shared/base-resolution.md), which terminates at a hardcoded `main` and lists the `gh repo view` lookup as an anti-pattern. The bridge keeps the lookup so it stays portable to repos whose default branch is not `main`; in this repo both resolve to `main`.

What the resolved base actually controls differs per path:

- **Swarm path** — passed through to `swarm` as `--base <branch>`. Independent section-issue PRs target it; dependent ones stack and retarget on merge.
- **Squad path** — reported to the operator only. `spawn-team` exposes no base override and always cuts the epic branch from `origin/main`.

### Section-to-issue mapping (swarm path)

For the swarm path, each `##` heading in `tasks.md` becomes one GitHub issue. The bridge:

1. Slugs the section heading to a stable section-id
2. Looks for an open issue with label `opsx-change:<name>` and body marker `<!-- opsx-section: <section-id> -->`
3. Reuses the matched issue or files a new one with the section's tasks inlined
4. Merges and dedupes the dependency edges from two sources:
   - **Inline**: `## Section B <!-- depends: section-a -->`
   - **Block**: `## Dependencies\nSection B blocked by Section A` at end of tasks.md

   A cycle in the merged set is refused up front by `read-change`, which aborts the dispatch.
5. Topologically orders the sections and wires a **linearized** `blocked-by` chain — each section-issue is blocked by only its immediate topological predecessor. Swarm's stacked-PR model is single-parent and has no fan-in handling, so a diamond-shaped change ends up over-constrained (never under-constrained): every original edge still holds transitively, because each branch contains its ancestors' work.

## Non-goals

- **Replacing `/opsx:apply`**. Stock single-agent mode remains the right choice for small linear changes.
- **Modifying squadkit or swarmkit**. The bridge calls them as black boxes through their existing public skill surface.
- **Auto-routing**. The operator picks `apply-via-squad` vs `apply-via-swarm` explicitly. The bridge does not heuristically choose.
- **Mixed-mode** (some tasks via squad, some via swarm in one change). Not supported in v1.

## Spec

The behavioral spec for this plugin lives at the repo root in [`openspec/specs/opsx-bridge/spec.md`](../../openspec/specs/opsx-bridge/spec.md).

## See also

- [OpenSpec](https://github.com/Fission-AI/OpenSpec) — the upstream spec-driven workflow
- `plugins/squadkit/` — multi-role coordinated dispatch
- `plugins/swarmkit/` — parallel isolated-worktree dispatch
