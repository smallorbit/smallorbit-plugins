# Squadkit

A Claude Code plugin for multi-agent team coordination. Squadkit introduces a small vocabulary — **roles**, **squads**, and **crews** — and ships the scaffolding needed to make team-based agent workflows reusable across any repository, regardless of language or tooling.

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

## Roles

The role library ships seven contracts under `plugins/squadkit/agents/`. Each role has a fixed model assignment chosen to match its cognitive load — orchestration and review run on Opus; implementation, exploration, and craft work run on Sonnet.

| Role | Model | Tools | Responsibility |
|------|-------|-------|----------------|
| **team-lead** | opus | Read, Grep, Glob, Bash, Edit, Write, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, Agent | Orchestrates the squad — dispatches work, gates exit conditions, owns no implementation. **The orchestrator (the session that ran `/squadkit:spawn-team`) IS the lead** — squadkit never spawns a separate `team-lead` agent. The contract file is the operating manual that session loads. |
| **architect** | opus | Read, Grep, Glob, Bash, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Read-only blueprint author — produces the contract a builder implements against. |
| **builder** | sonnet | Read, Edit, Write, Grep, Glob, Bash, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Implements the architect's blueprint in an isolated worktree and opens the PR. |
| **reviewer** | opus | Read, Grep, Glob, Bash, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Read-only PR auditor — sole authority that clears a PR for merge. |
| **tester** | sonnet | Read, Edit, Write, Grep, Glob, Bash, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Authors and maintains the test suite that backs the squad's verify gate. |
| **explorer** | sonnet | Read, Grep, Glob, Bash, WebFetch, WebSearch, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Read-only research role for scoped investigative questions. |
| **designer** | sonnet | Read, Edit, Write, Grep, Glob, Bash, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet | Owns UX flows, mockups, design tokens, and accessibility checks. |

Override a shipped contract for a single repo by dropping `.claude/agents/<role>.md` into the repo root — the `SessionStart` hook (see [Hooks](#hooks)) prefers the local override and falls back to the plugin-shipped contract.

**Cooperative shutdown.** Every role contract (lead and members) documents a cooperative `shutdown_request` / `shutdown_response approve:true` handshake. The lead initiates teardown by polling every active member; each member replies before exiting. Without these approvals `TeamDelete` cleans the registry but leaves the underlying iterm2/tmux panes stranded — burning context and quota until the user manually closes them. If you author a project-local override at `.claude/agents/<role>.md`, preserve the cooperative-shutdown section verbatim.

### Tools allowlist and harness augmentation

The role contracts now declare the **full** tool set each role uses, including the squad-coordination tools (`SendMessage`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, and `Agent` for `team-lead`). A reader of `team-lead.md` can see from frontmatter alone that the role can dispatch work — no mental model of harness magic required.

Historically the Claude Code harness augmented the allowlist for some of these tools at spawn time (a spawned `team-lead` could call `SendMessage` even when its frontmatter omitted it). That augmentation still happens, but explicit declaration is preferred for documentation correctness and to keep the contracts honest about what each role actually does.

**Override caveat.** If you author a project-local overlay at `.claude/agents/<role>.md`, preserve the coordination tools in the `tools:` line. Stripping them risks breaking dispatch — depending on overlay merge semantics, a restricted overlay may shadow harness augmentation and leave the role unable to message teammates or maintain the dispatch queue. When in doubt, copy the shipped contract's `tools:` line verbatim and add to it rather than replace it.

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **init** | `/squadkit:init` | Interview-driven generator that writes `.squadkit/config.json` to the repo root. No per-stack presets — the wizard asks you for the commands directly. |
| **spawn-team** | `/squadkit:spawn-team` | Spawn a crew from a profile. Resolves a phonetic team name, optionally cuts an epic feature branch, provisions per-builder worktrees, registers the team via `TeamCreate`, and waits for one idle notification per spawned member (the harness's readiness signal) before the orchestrator (which IS the lead) enters its dispatch loop. |
| **agent-team-retro** | `/squadkit:agent-team-retro` | Run a retrospective on the currently-spawned squad. Polls each active member with three fixed questions, aggregates findings into severity-grouped action items, applies approved edits to role contracts, and optionally hands findings off to `speckit:catalog` as GitHub issues. |

A `role-spec` skill for authoring new role contracts ships in a subsequent release.

## Crews

A **crew profile** is a YAML file under `plugins/squadkit/crews/` describing a reusable roster shape. `spawn-team` loads a profile, applies CLI overrides (`--with`, `--without`, `--builders`), and materializes the resolved roster.

### Starter profiles

| Profile | Roster | When to use |
|---------|--------|-------------|
| **all-rounder** | team-lead, architect, builder×2, reviewer, tester, explorer, designer | Full-spectrum feature work end-to-end. |
| **builder** | architect, builder×2, reviewer, tester | Straight execution against an already-locked implementation contract. Subset of all-rounder without explorer/designer. |
| **design** | architect, designer, explorer | Discovery-stage exploration with no implementation yet. Read-only: produces issue comments, no worktrees, no epic branch. (`kind: discovery`) |
| **discovery-3-role** | architect, explorer, designer | Read-only early-stage discovery — architect frames the system, explorer investigates prior art, designer shapes the surface. Deliverables are issue comments. (`kind: discovery`) |
| **qa** | team-lead, reviewer, tester, builder×1 | Hardening, regression, bug-fix sweeps. |

### Schema

Each crew YAML conforms to:

```yaml
name: <string>            # profile name; matches the filename without .yaml
description: <string>     # one-line summary of when to use this crew
kind: <string>            # optional, default "execution"; execution | discovery
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
| `--issues <range>` | none | Issue numbers / ranges to load as the team's initial backlog (swarmkit grammar: `1319,1329,1331` or `1319-1337`). Resolved via `swarmkit:gh-fetch-issues` and forwarded to the lead's first dispatch prompt as a structured backlog table. Trailing-narrative form (`to tackle issues 1319-1337`) is also accepted. |
| `--brief <text\|@path>` | none | Mission brief embedded into the architect's spawn prompt. Inline text or `@path` to a file. **Required when the resolved profile has `kind: discovery`.** Optional and otherwise ignored when `kind: execution`. |
| `--mode <inherit\|auto\|bypass>` | `inherit` | Permission mode for spawned members. `inherit`: no override; harness defaults apply. `auto`: pass `mode: "auto"` to every spawn AND force `model: "opus"` for non-builder roles (sonnet members prompt for permissions in auto mode). `bypass`: pass `mode: "bypassPermissions"`; model stays default. Pass when the orchestrator runs in `auto` or `bypassPermissions` so spawned members inherit the same authority. |

### Phonetic naming convention

If `--name` is not given, `spawn-team` derives a team name from the repo plus the next available NATO phonetic letter:

```
<repo>-alpha, <repo>-bravo, <repo>-charlie, …, <repo>-zulu
```

It scans `~/.claude/teams/<repo>-*` and picks the first letter without a `config.json`. If every letter is taken, the skill stops and asks the user to recycle a stale team or pass `--name` explicitly — it never invents a 27th letter.

### Epic feature-branch convention

`spawn-team` integrates with the flowkit epic flow. When you pass `--epic <slug>`, the skill:

1. Resolves `<issue>` from the `--epic` argument shape (or prompts when omitted).
2. Invokes `flowkit:cut-epic` (idempotent against existing branches; pins `claude.flowkit.prBase`; pushes to origin).

If `--epic` is not provided, the skill prompts whether to cut one or run on the base branch directly.

See the related flowkit skill:

- [`flowkit:cut-epic`](../flowkit/skills/cut-epic/SKILL.md) — the primitive that `spawn-team --epic` invokes.

### Idempotency and per-builder worktrees

- **Idempotent** — re-running `spawn-team` against an existing `~/.claude/teams/<name>/config.json` never duplicates live members. The skill reports the existing roster and asks whether to reuse, add missing members, or cancel.
- **Worktrees** — multi-builder configs (>1 builder) provision per-member worktrees under `.claude/worktrees/<member>/` via manual `git worktree add --detach <path> <work-branch>`. Detached HEAD avoids the branch-ref contention that would otherwise fail on `git worktree add` when the main worktree already holds the work branch. Builders create per-issue branches (e.g. `worktree-agent-<issue>`) off the detached commit when they pick up a task. Singleton-builder profiles share the workspace; no worktree is created.
- **Env-file seeding** — after each per-builder worktree is created, `spawn-team` auto-copies the repo's gitignored env files (`.env.local`, `.env.test.local`, etc.) into the worktree so builders can run the verify suite without manual setup. Override the auto-detection with the optional `worktreeSeed` config key (see [Configuration](#configuration) → Schema).
- **Stale-worktree detection** — if a `.claude/worktrees/<member>/` already exists on a non-matching branch from a prior session, `spawn-team` prompts (sweep / reuse / abort) before reusing. It also calls `swarmkit:clean-worktrees` as a pre-flight when stale paths exist that don't match the resolved roster.

## Hooks

Squadkit ships a `SessionStart` hook (`hooks/pickup-team-context.sh`) that re-asserts role context whenever a session starts — both fresh sessions spawned by `spawn-team` and resumed sessions picked up via `sessionkit:pickup`.

**When it fires**: every Claude Code `SessionStart` event. The hook scans `~/.claude/teams/*/config.json`, matches the current session by `leadSessionId` (preferred) or by member `cwd`, and stops at the first match. If no team matches, it exits silently with no output.

**What it emits**: a single `systemMessage` reminder telling the lead (or matched member) to load its role contract from disk. The path resolution prefers a project-local override at `.claude/agents/<role>.md` and falls back to the plugin-shipped contract at `plugins/squadkit/agents/<role>.md`.

**Why `SessionStart` only**: the same event fires for both startup paths the issue calls out — fresh `spawn-team` leads and `sessionkit:pickup`-resumed leads — so a single hook covers both without leaning on `PostToolUse` matchers. This keeps team-context restoration owned end-to-end by squadkit; sessionkit no longer needs to know about teams.

**Override pattern**: drop a customized role file at `.claude/agents/<role>.md` in your repo (e.g. `.claude/agents/team-lead.md`) to override the shipped contract for that repo. The hook's reminder will point the agent at the override automatically.

## Configuration

Squadkit reads its per-repo configuration from `.squadkit/config.json` at the repo root. Generate it once with `/squadkit:init`; edit by hand thereafter.

### Init walkthrough

Run `/squadkit:init` once per repo. The wizard is fully interview-driven — there are no per-stack presets and no auto-detection. It asks five questions sequentially and surfaces the running config back to you after each answer:

1. **Typecheck command** — e.g. `npm run typecheck`, `mypy .`, `cargo check`. Empty answer means "this repo has no typecheck step."
2. **Test command** — e.g. `npm test`, `pytest`, `cargo test`. Empty answer means "no test step."
3. **Lint command** — optional. e.g. `npm run lint`, `ruff check`, `cargo clippy`. Empty answer means "no lint step." The reviewer uses this to scope lint errors to PR-touched files.
4. **Install command** — e.g. `npm install`, `pip install -e .`, `cargo fetch`. Empty answer means "no install step."
5. **Base branch** — defaults to `develop`. Most repos accept the default.

The wizard then writes `.squadkit/config.json` (pretty-printed, two-space indent) to the **main repo root** — never to a worktree, even when invoked from inside one. If the file already exists, the wizard surfaces its current contents and prompts before overwriting.

### Schema

```json
{
  "verify": {
    "typecheck": "<command>",
    "test": "<command>",
    "lint": "<command>"
  },
  "install": "<command>",
  "baseBranch": "<branch>",
  "worktreeSeed": ["<repo-relative-path>", "..."]
}
```

| Field | Purpose |
|-------|---------|
| `verify.typecheck` | Command a role agent runs to validate types before opening a PR (e.g. `npm run typecheck`, `mypy .`, `cargo check`). Empty string if the project has no typecheck step. |
| `verify.test` | Command a role agent runs to validate behavior before opening a PR (e.g. `npm test`, `pytest`, `cargo test`). Empty string if the project has no test step. |
| `verify.lint` | Optional. Command the reviewer runs to scope lint errors to PR-touched files (e.g. `npm run lint`, `ruff check`, `cargo clippy`). Omit or set to empty string if the project has no lint step. |
| `install` | Command a fresh worktree runs to install dependencies (e.g. `npm install`, `pip install -e .`, `cargo fetch`). Empty string if no install step is needed. |
| `baseBranch` | Default base branch for PRs opened by squad members. Most repos use `develop` or `main`. |
| `worktreeSeed` | Optional. Explicit list of repo-relative paths to copy into every per-builder worktree at spawn time. When present, overrides `spawn-team`'s auto-detection of ignored env files. Use for projects that need non-env files seeded too (certificates, config snippets, etc.). When absent, `spawn-team` auto-detects ignored env files matching `^(\.env(\.local|\.[a-z-]+\.local)?\|\.env-[a-z-]+)$` via `git ls-files --others --ignored --exclude-standard`. |

Future role contracts and crew profiles will reference these values rather than hardcoding stack-specific commands, making the same role definitions reusable across every repo.

## Pairing with Other Plugins

Squadkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Squadkit complements the rest of the suite:

- **[swarmkit](../swarmkit)** — `/swarm` spawns one agent per GitHub issue. Squadkit is the longer-running, role-aware sibling for crew workflows.
- **[flowkit](../flowkit)** — squad members open PRs through flowkit-shaped commits and conventions.
- **[sessionkit](../sessionkit)** — `/handoff` and `/pickup` capture and restore generic session state (goal, git, tasks, context). Squadkit's `SessionStart` hook layers team-role context on top, so members resumed via `/pickup` automatically reload their role contract.

## Roadmap

- `role-spec` skill for authoring new role contracts.
- Additional starter crew profiles (e.g. spike, migration, hotfix).

See the parent epic for the full plan.
