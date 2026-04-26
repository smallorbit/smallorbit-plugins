# Squadkit

A Claude Code plugin for multi-agent team coordination. Squadkit introduces a small vocabulary — **roles**, **squads**, and **crews** — and ships the scaffolding needed to make team-based agent workflows reusable across any repository, regardless of language or tooling.

> Status: **early scaffold (v0.1.0).** This release ships only the plugin skeleton and the `init` config wizard. Role contracts, crew profiles, the spawn-team skill, and the retro skill land in subsequent releases.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install squadkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/squadkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Vocabulary

Squadkit's coordination model is intentionally small:

| Term | Definition |
|------|------------|
| **Role** | A single agent with a focused contract (e.g. *implementer*, *reviewer*, *integrator*). One role definition, one agent. |
| **Squad** | A role-cohesive group of agents collaborating on one slice of work — for example, three implementers fanning out across files in the same feature. |
| **Crew** | A team-lead orchestrating one or more squads end-to-end. The crew is the unit you spawn and ship with. |

Downstream skills will let you assemble crews from the role library and dispatch them against issues, epics, or freeform prompts.

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **init** | `/squadkit:init` | Interview-driven generator that writes `.squadkit/config.json` to the repo root. No per-stack presets — the wizard asks you for the commands directly. |

More skills (spawn-team, retro, role-spec) ship in subsequent releases.

## Configuration

Squadkit reads its per-repo configuration from `.squadkit/config.json` at the repo root. Generate it once with `/squadkit:init`; edit by hand thereafter.

### Schema

```json
{
  "verify": {
    "typecheck": "<command>",
    "test": "<command>"
  },
  "install": "<command>",
  "baseBranch": "<branch>"
}
```

| Field | Purpose |
|-------|---------|
| `verify.typecheck` | Command a role agent runs to validate types before opening a PR (e.g. `npm run typecheck`, `mypy .`, `cargo check`). Empty string if the project has no typecheck step. |
| `verify.test` | Command a role agent runs to validate behavior before opening a PR (e.g. `npm test`, `pytest`, `cargo test`). Empty string if the project has no test step. |
| `install` | Command a fresh worktree runs to install dependencies (e.g. `npm install`, `pip install -e .`, `cargo fetch`). Empty string if no install step is needed. |
| `baseBranch` | Default base branch for PRs opened by squad members. Most repos use `develop` or `main`. |

Future role contracts and crew profiles will reference these values rather than hardcoding stack-specific commands, making the same role definitions reusable across every repo.

## Pairing with Other Plugins

Squadkit complements the rest of the suite:

- **[swarmkit](../swarmkit)** — `/swarm` spawns one agent per GitHub issue. Squadkit is the longer-running, role-aware sibling for crew workflows.
- **[flowkit](../flowkit)** — squad members open PRs through flowkit-shaped commits and conventions.
- **[sessionkit](../sessionkit)** — `/handoff` and `/pickup` already understand multi-agent team state, so squad members survive context limits.

## Roadmap

- Role contracts and a starter library (implementer, reviewer, integrator).
- `crews/` profiles assembling roles into reusable crew shapes.
- `spawn-team` skill that materializes a crew from a profile.
- `retro` skill for post-crew reflection and skill discovery.

See the parent epic for the full plan.
