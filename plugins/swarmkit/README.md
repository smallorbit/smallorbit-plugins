# Swarmkit

A Claude Code plugin that resolves GitHub issues with parallel agents. Pick what to work on, swarm it with isolated worktree agents, merge PRs in dependency order, and keep your branches clean — all from slash commands.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install swarmkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/swarmkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with repo access
- Git configured with push access to your target repos

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **swarm** | `/swarm` | Spawn parallel isolated-worktree agents to resolve GitHub issues. Supports one-shot mode (specific issues) and loop mode (clear the board). Auto-creates PRs targeting `develop`. |
| **pick-issue** | `/pick-issue` | Fetches open issues, ranks them by priority, specificity, and architectural impact, and recommends what to work on next. |
| **clean-worktrees** | `/clean-worktrees` | Removes all agent worktrees and their orphaned `worktree-agent-*` branches. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **self-review** | swarm | Runs iterative `/simplify` passes on changed files before PR creation. |
| **conventional-commit-message** | swarm | Enforces `type(scope): description` commit format. |
| **gh-fetch-issues** | pick-issue, swarm | Fetches open issues and filters out `on-hold` labeled ones. |
| **gh-label-merged-issues** | swarm | Applies `merged-to-develop` label to issues referenced in merged PRs. |
| **issue-rank** | pick-issue, swarm | Ranks issues by priority labels, specificity, and architectural impact. |

## Typical Workflow

```
/pick-issue                          # See what's ready to work on
/swarm 12 15 18                      # Resolve specific issues in parallel
/swarm                               # Or clear the entire board in a loop
/clean-worktrees                     # Tidy up after a swarm run
```

## How Swarm Works

1. Ensures a `develop` branch exists (creates from `main` if needed)
2. Fetches issues, analyzes dependencies, and presents a swarm plan
3. Spawns one agent per issue (or grouped set) in isolated git worktrees
4. Each agent: creates branch, makes changes, commits, pushes, opens PR
5. Merges PRs in dependency order via squash merge
6. Cleans up worktrees and orphaned branches

**One-shot mode**: `/swarm 12 15 18` — resolve those issues and stop.
**Loop mode**: `/swarm` — fetch, swarm, merge, repeat until the board is clear.
**Label filter**: `/swarm bug` — loop mode, but only `bug`-labeled issues.

### Flags

- `--model <sonnet|opus>` — override model selection for all agents
- `--base <branch>` — override the default base branch (`develop`)
- `--auto` — skip approval gates and proceed automatically

## Assumptions & Conventions

Swarmkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: `develop` → `main`

By default, all PRs target a `develop` branch. If `develop` doesn't exist, `/swarm` creates it from `main` automatically.

This assumes a **release-branch workflow**: feature work lands in `develop`, and a release process promotes `develop` → `main`. Issues are intentionally left open after their PRs merge to `develop`; they're closed when the release ships.

**If you use trunk-based development** (everything goes to `main`):

```bash
/swarm --base main 12 15 18   # one-shot, targeting main
/swarm --base main            # loop mode, targeting main
```

### Branch Naming: `worktree-agent-<issue>`

Every agent branch follows this exact pattern (e.g., `worktree-agent-42`). This naming convention is what `/clean-worktrees` uses to identify and remove orphaned branches. It is not configurable.

### Commit Format: Conventional Commits

All commits produced by swarm agents follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Common types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`. The `conventional-commit-message` sub-skill enforces this format.

### Label: `merged-to-develop`

After a PR merges, `/swarm` applies the `merged-to-develop` label to the referenced issues. This label is auto-created in your repo if it doesn't exist.

### Issue Lifecycle

Swarmkit **never closes issues** — that's intentional. Closing is left to the release process (when your base branch merges to `main`). This keeps issues open and visible on the board until the work is actually shipped.

## Configuration Notes

- **`swarm`** has `disable-model-invocation: true` — it only runs when you explicitly type `/swarm`, never auto-triggered by Claude. This prevents accidental mass agent spawning.
- **`pick-issue`** and **`clean-worktrees`** allow model invocation, so Claude can suggest or invoke them contextually.

## Pairing with Speckit

Swarmkit executes work; [speckit](../speckit) defines it. Use them together for the full planning-to-execution loop:

```
/spec add CSV export              # Plan the feature, file issues
/pick-issue                       # Confirm what to work on
/swarm                            # Resolve with parallel agents
/clean-worktrees                  # Clean up
```
