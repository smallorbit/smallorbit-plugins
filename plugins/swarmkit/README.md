# Swarmkit

A Claude Code plugin that resolves GitHub issues with parallel agents. Pick what to work on, swarm it with isolated worktree agents, merge PRs in dependency order, and keep your branches clean — all from slash commands.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers install, `/spec`, and `/swarm` end to end.

**Already here for swarmkit specifically?** Read [METHODOLOGY.md](./METHODOLOGY.md) for the full narrative on how the stacked agent/PR workflow fits together — worktree isolation, stacked branches, top-down merging with reference accumulation, and loop mode.

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

## Permissions

Swarmkit is designed to run best when agents don't have to pause for per-command approvals.

**Recommendation.** Run your Claude Code session in `bypassPermissions` mode, or pre-approve an allowlist covering the commands swarm agents rely on (`git`, `gh`, and `bash` for internal tooling). See the Anthropic docs on [Claude Code permission modes](https://code.claude.com/docs/en/permission-modes) for the authoritative how-to — setting a default mode, starting a session with `--permission-mode`, and configuring allow/ask/deny rules.

**Why.** Parallel agents working in isolated worktrees cannot usefully pause for per-command approvals — the whole point of the swarm is that they run concurrently, and interactive prompts defeat that.

**Safety caveats.** These share billing with the recommendation, not footnote status:

- Only use `bypassPermissions` on trusted repositories.
- Only use it when you're willing for agents to push branches and open PRs without per-action review.
- Isolated-worktree scoping limits blast radius to the repo, but a buggy or malicious agent could still commit and push harmful code.
- Swarmkit leaves PRs open for human review by design — do not skip reviewing PRs before merging.

**Agent-level bypass is already applied.** Swarm spawns each agent internally with `mode: "bypassPermissions"` so the agent itself runs without prompts; the user-facing question is whether you also want the same mode at the session level that orchestrates them.

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **swarm** | `/swarm` | Spawn parallel isolated-worktree agents to resolve GitHub issues. Supports one-shot mode (specific issues) and loop mode (clear the board). Auto-creates PRs targeting `develop`. |
| **swarm-experimental** | `/swarm-experimental` | Experimental parallel variant of `/swarm`. Script-backed mechanical phases (preflight, teardown) reduce model round-trips. Same arg grammar and behavior as `/swarm` — prefer `/swarm` for stable workflows. |
| **next-issue** | `/next-issue` | Fetches open issues, ranks them by priority, specificity, and architectural impact, and recommends what to work on next. |
| **merge-stack** | `/merge-stack` | Merges all open swarm PRs top-down (leaf PRs first, root last). |
| **clean-worktrees** | `/clean-worktrees` | Removes all agent worktrees and their orphaned `worktree-agent-*` branches. |
| **clean-remote-worktrees** | `/clean-remote-worktrees` | Sweeps orphaned remote `worktree-agent-*` branches from the remote. |
| **squad** (experimental) | `/squad` | Agent Teams variant of `/swarm` — runs a structured lead/builder/reviewer team. See [Experimental features](#experimental-features). |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **conventional-commit-message** | swarm | Enforces `type(scope): description` commit format. |
| **gh-fetch-issues** | next-issue, swarm | Fetches open issues and filters out `on-hold` labeled ones. |
| **issue-rank** | next-issue, swarm | Ranks issues by priority labels, specificity, and architectural impact. |

## Typical Workflow

```
/next-issue                          # See what's ready to work on
/swarm 12 15 18                      # Resolve specific issues in parallel
/merge-pr       # If one PR — merge it directly (flowkit skill)
/merge-stack    # If two or more PRs — merges top-down: leaf PRs first, root last
/swarm                               # Or clear the entire board in a loop
/clean-worktrees                     # Tidy up after a swarm run
```

## How Swarm Works

1. Ensures a `develop` branch exists (creates from `main` if needed)
2. Fetches issues, analyzes dependencies, and presents a swarm plan
3. Spawns one agent per issue (or grouped set) in isolated git worktrees
4. Each agent: creates branch, makes changes, commits, pushes, opens PR — then stops
5. Use `/merge-pr` (1 PR, from [flowkit](../flowkit)) or `/merge-stack` (2+ PRs) to merge into `develop` — top-down: leaf PRs first, root last
6. Cleans up worktrees and orphaned branches

**One-shot mode**: `/swarm 12 15 18` — resolve those issues and stop.
**Loop mode**: `/swarm` — fetch, swarm, open PRs, repeat until the board is clear.
**Label filter**: `/swarm bug` — loop mode, but only `bug`-labeled issues.

### Flags

- `--model <sonnet|opus>` — override model selection for all agents
- `--base <branch>` — override the default base branch (`develop`)

## Assumptions & Conventions

Swarmkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: `develop` → `main`

By default, all PRs target a `develop` branch. If `develop` doesn't exist, `/swarm` creates it from `main` automatically.

This assumes a **release-branch workflow**: feature work merges into `develop`, and a release process promotes `develop` → `main`. Issues are intentionally left open after their PRs merge to `develop`; they're closed when the release ships.

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

### Label: `status:in-progress`

When an agent is spawned for an issue, swarmkit applies `status:in-progress` to it. This prevents `gh-fetch-issues` and `next-issue` from re-selecting it in subsequent swarm cycles. GitHub auto-closes the issue when its PR merges (via `Closes #N`), so no manual label cleanup is needed.


### Issue Lifecycle

Swarmkit **never closes issues** — that's intentional. Closing is left to the release process (when your base branch merges to `main`). This keeps issues open and visible on the board until the work is actually shipped.

## Configuration Notes

- **`swarm`** has `disable-model-invocation: true` — it only runs when you explicitly type `/swarm`, never auto-triggered by Claude. This prevents accidental mass agent spawning.
- **`next-issue`** and **`clean-worktrees`** allow model invocation, so Claude can suggest or invoke them contextually.

## Pairing with Other Plugins

Swarmkit executes work; [speckit](../speckit) defines it. Use them together for the full planning-to-execution loop:

```
/spec add CSV export              # Plan the feature, file issues
/next-issue                       # Confirm what to work on
/swarm                            # Resolve with parallel agents
/clean-worktrees                  # Clean up
```

[Sessionkit](../sessionkit) complements swarmkit throughout: use `/handoff` to preserve state when context runs low mid-swarm, and `/skillit` after a swarm to capture reusable patterns that emerged.

## Experimental features

### `swarm-experimental`

A parallel, experimental variant of `/swarm`. It accepts the same arguments and produces the same outcomes, but collapses deterministic mechanical phases — preflight, issue gathering, post-agent verification, and loop-mode teardown — into shell scripts rather than conversational model steps. This reduces model round-trips for work that doesn't require judgment.

**When to use it**: dogfooding script-extraction changes or benchmarking round-trip reduction. `/swarm` remains the stable entry point — if anything misbehaves, fall back to it.

```
/swarm-experimental 12 15 18
```

No special setup is required beyond what `/swarm` needs. See [Prerequisites](#prerequisites) and [Permissions](#permissions).

### `squad`

An [Agent Teams](https://code.claude.com/docs/en/agent-teams)-based variant of `/swarm`. Instead of fully independent isolated agents, it runs a structured team: a lead (the main session) coordinates N builder teammates and 1 dedicated reviewer teammate. The reviewer runs continuously alongside the builders — providing feedback before any PR is pushed — and uses peer notifications to stay in sync.

**Setup**: `/squad` requires the Agent Teams API to be enabled. See [SETUP.md](./SETUP.md) for the three ways to set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and how to verify it.

Once enabled, invoke it the same way as `/swarm`:

```
/squad 12 15 18
```

**Known limits**:

- **One team per session** — Agent Teams supports only a single active team per Claude Code session. Running multiple concurrent swarms in the same session is not supported.
- **No session resumption** — if the Claude Code session dies, the entire team goes with it. There is no way to reconnect or hand off to a new session.
- **Halt-only on teammate crash** — if a builder or reviewer crashes, the swarm halts. There is no automatic respawning in v1.
- **Reviewer is pre-push only** — the reviewer teammate provides feedback before PRs are opened. It does not perform GitHub-side code review after the PR is created.
- **In-process backend ignores `isolation: "worktree"`** — today's default Agent Teams backend silently drops the flag, leaving builders in the orchestrator's cwd. The squad builder contract includes a temporary manual-worktree fallback that creates the worktree itself when this happens. See [#362](https://github.com/smallorbit/smallorbit-plugins/issues/362) — the fallback will be removed once the backend honors the flag.
- **Experimental** — API and behavior may change without notice as the Agent Teams feature evolves.
