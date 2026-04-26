# Squadkit

A Claude Code plugin for multi-agent team coordination. Squadkit introduces a small vocabulary — **roles**, **squads**, and **crews** — and ships the scaffolding needed to make team-based agent workflows reusable across any repository, regardless of language or tooling.

> Status: **early scaffold.** This release ships the plugin skeleton, the `init` config wizard, role contracts, the `spawn-team` skill, and the starter crew profiles. The `retro` skill lands in a subsequent release.

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
| **spawn-team** | `/squadkit:spawn-team` | Spawn a crew from a profile. Resolves a phonetic team name, optionally cuts an epic feature branch, provisions per-builder worktrees, and waits for `SendMessage` acks before declaring the team ready. |

More skills (`retro`, `role-spec`) ship in subsequent releases.

## Crews

A **crew profile** is a YAML file under `plugins/squadkit/crews/` describing a reusable roster shape. `spawn-team` loads a profile, applies CLI overrides (`--with`, `--without`, `--builders`), and materializes the resolved roster.

### Starter profiles

| Profile | Roster | When to use |
|---------|--------|-------------|
| **all-rounder** | team-lead, architect, builder×2, reviewer, tester, explorer, designer | Full-spectrum feature work end-to-end. |
| **design** | team-lead, architect, designer, explorer | Discovery-stage exploration with no implementation yet. |
| **qa** | team-lead, reviewer, tester, builder×1 | Hardening, regression, bug-fix sweeps. |

### Schema

Each crew YAML conforms to:

```yaml
name: <string>            # profile name; matches the filename without .yaml
description: <string>     # one-line summary of when to use this crew
members:
  - role: <string>        # one of: team-lead, architect, builder, reviewer, tester, explorer, designer
    count: <int>          # optional, default 1; 1–5 for builder
```

Example:

```yaml
name: all-rounder
description: Full-spectrum crew for end-to-end feature work.
members:
  - role: team-lead
  - role: architect
  - role: builder
    count: 2
  - role: reviewer
  - role: tester
  - role: explorer
  - role: designer
```

`team-lead` is implicit — `spawn-team` re-adds it if a profile or override removes it. Builder count is capped at 5; values above are clamped with a warning.

### `spawn-team` flag matrix

| Flag | Default | Effect |
|------|---------|--------|
| `--profile <name>` | `all-rounder` | Load `plugins/squadkit/crews/<name>.yaml`. |
| `--builders <N>` | `2` | Override the builder count from the profile (cap 5). |
| `--with <role>` | none | Append a role to the resolved roster. Repeatable. |
| `--without <role>` | none | Remove every member with the given role. Repeatable. |
| `--name <custom>` | auto | Override the team name; skips phonetic auto-naming. |
| `--epic <slug>` | none | Cut `feature/<slug>-<issue>` from the configured base branch and pin `claude.flowkit.prBase` for the session. If omitted, the skill prompts. |

### Phonetic naming convention

If `--name` is not given, `spawn-team` derives a team name from the repo plus the next available NATO phonetic letter:

```
<repo>-alpha, <repo>-bravo, <repo>-charlie, …, <repo>-zulu
```

It scans `~/.claude/teams/<repo>-*` and picks the first letter without a `config.json`. If every letter is taken, the skill stops and asks the user to recycle a stale team or pass `--name` explicitly — it never invents a 27th letter.

### Epic feature-branch convention

`spawn-team` integrates with the flowkit epic flow. When you pass `--epic <slug>`, the skill:

1. Reads `baseBranch` from `.squadkit/config.json` (defaults to `develop` if missing).
2. Cuts `feature/<slug>-<issue>` from `origin/<baseBranch>` (idempotent against existing branches).
3. Pushes the branch to origin.
4. Pins `claude.flowkit.prBase` so every member PR opened during the session targets the epic branch.

If `--epic` is not provided, the skill prompts whether to cut one or run on the base branch directly.

See the related flowkit skills:

- [`flowkit:cut-epic`](../flowkit/skills/cut-epic/SKILL.md) — standalone epic cut, equivalent to the inline cut performed by `spawn-team --epic`.
- [`flowkit:preview-epic`](../flowkit/skills/preview-epic/SKILL.md) — preview the epic-to-base diff before opening the final integration PR.

### Idempotency and per-builder worktrees

- **Idempotent** — re-running `spawn-team` against an existing `~/.claude/teams/<name>/config.json` never duplicates live members. The skill reports the existing roster and asks whether to reuse, add missing members, or cancel.
- **Worktrees** — multi-builder configs (>1 builder) provision per-member worktrees under `.claude/worktrees/<member>/` via manual `git worktree add`. Singleton-builder profiles share the workspace; no worktree is created.

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

- `retro` skill for post-crew reflection and skill discovery.
- `role-spec` skill for authoring new role contracts.
- Additional starter crew profiles (e.g. spike, migration, hotfix).

See the parent epic for the full plan.
