# Swarmkit

A Claude Code plugin that resolves GitHub issues with parallel agents. Pick what to work on, swarm it with isolated worktree agents, merge PRs in dependency order, and keep your branches clean — all from slash commands.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers install, `/spec`, and `/swarm` end to end.

**Already here for swarmkit specifically?** Read [METHODOLOGY.md](./METHODOLOGY.md) for the full narrative on how the stacked agent/PR workflow fits together — worktree isolation, stacked branches, bottom-up merging with up-front retargeting, and loop mode.

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
| **swarm** | `/swarm` | Spawn parallel isolated-worktree agents to resolve GitHub issues, then run an automatic review/fix pass on each PR. Multi-issue/loop/label runs auto-cut a `feature/<slug>-<N>` branch from `main` and route all child PRs to it (operator squash-merges epic→main to close out). Single-issue one-shot runs target `main` directly. |
| **next-issue** | `/next-issue` | Fetches open issues, ranks them by priority, specificity, and architectural impact, and recommends what to work on next. |
| **merge-stack** | `/merge-stack` | Merges all open swarm PRs bottom-up (root PRs first, leaves last) after retargeting non-root PRs to `$BASE`. Pre-scans worktrees to flag merge-set branches still held locally and tails the report with a `/clean-worktrees` follow-up when any `worktree-agent-*` paths remain. |
| **clean-worktrees** | `/clean-worktrees` | Removes all agent worktrees and their orphaned `worktree-agent-*` branches. |
| **clean-remote-worktrees** | `/clean-remote-worktrees` | Sweeps orphaned remote `worktree-agent-*` branches from the remote. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **conventional-commit-message** | swarm | Enforces `type(scope): description` commit format. |
| **gh-fetch-issues** | next-issue, swarm | Fetches open issues and filters out `on-hold` labeled ones. |
| **issue-rank** | next-issue, swarm | Ranks issues by priority labels, specificity, and architectural impact. |

### Agents

Swarmkit vendors a specialized reviewer agent used by `/swarm`'s automatic review/fix pass. It is not a general-purpose reviewer — it is purpose-built for comparing a swarm-produced PR against its originating issue.

| Agent | Used by | Purpose |
|-------|---------|---------|
| **swarm-reviewer** | swarm | Reviews a swarm PR against the originating issue's acceptance criteria. Returns findings inline (never via `gh pr comment`) using a fixed five-section output structure: Verdict / Blockers / Concerns / Nits / Coverage gaps. |

## Typical Workflows

### Multi-issue (auto-cuts an epic branch)

```
/next-issue                          # See what's ready to work on
/swarm 12 15 18                      # Auto-cuts feature/<slug>-<N> from main, opens PRs against it
/merge-stack                         # Squash-merge child PRs into the epic branch bottom-up
# verify on the epic branch          # typecheck/test/lint
# open + squash-merge epic→main PR   # then unset claude.flowkit.prBase and delete epic branch
```

### Single issue (flat to main)

```
/swarm 12                            # No epic cut — PR targets main directly
/merge-pr                            # Squash-merge the one PR (flowkit skill)
```

### Loop mode (clear the board)

```
/swarm                               # Fetch, swarm, open PRs, repeat until nothing's left
/clean-worktrees                     # Tidy up after a swarm run
```

## How Swarm Works

1. Verifies `main` exists on origin and the working tree is ready
2. Fetches issues, analyzes dependencies, and presents a swarm plan
3. If the run will spawn ≥2 agents, cuts a `feature/<slug>-<N>` branch from `origin/main` inline (idempotent — resumes the branch if it already exists on origin) and pins `claude.flowkit.prBase` to it — all spawned PRs target the epic branch
4. Spawns one agent per issue (or grouped set) in isolated git worktrees
5. Each agent: creates branch, makes changes, commits, pushes, opens PR — then stops
6. Runs an automatic review/fix pass on each PR (see [The Review/Fix Pass](#the-reviewfix-pass) below)
7. Use `/merge-pr` (1 PR, from [flowkit](../flowkit)) or `/merge-stack` (2+ PRs) to squash-merge child PRs into the epic branch bottom-up; then open a single PR from the epic to `main`, squash-merge it, unpin, and delete the epic branch
8. Cleans up worktrees and orphaned branches

**One-shot mode**: `/swarm 12 15 18` — auto-cuts epic branch, opens PRs against it; use `/merge-stack` then a final epic→main squash to land.
**Single issue (one-shot)**: `/swarm 12` — flat to `main`, no epic cut; use `/merge-pr` to merge.
**Loop mode**: `/swarm` — fetch, swarm, open PRs, repeat until the board is clear; epic branch is cut once and reused across cycles.
**Label filter**: `/swarm bug` — loop mode, but only `bug`-labeled issues.

### Flags

- `--model <sonnet|opus>` — override model selection for all builder agents
- `--base <branch>` — override the default base branch (`main`); also suppresses the epic cut
- `--no-epic` — suppress feature-branch mode for this run; PRs target `$BASE` directly
- `--epic <slug>` — explicit slug for the auto-cut epic branch
- `--reviewer-model <sonnet|opus>` — override the review-pass reviewer model (default: `sonnet`)
- `--worker-model <sonnet|opus>` — override the fix-round worker model (default: `sonnet`)

## The Review/Fix Pass

Every PR `/swarm` opens passes through an automatic review/fix pass before the run completes — always-on, with no flag to disable it:

1. As each swarm agent finishes, immediately dispatches `swarm-reviewer` against that PR in the background — no waiting for other swarm agents.
2. The reviewer compares the PR diff against the originating issue's acceptance criteria and returns findings inline (never as a `gh pr comment`).
3. If the reviewer's verdict is clean (Approve, no blockers, no concerns, no recommended coverage gaps), the PR is left as-is.
4. If the reviewer surfaces blockers or concerns, a worker agent is spawned to address them. The worker branches from the existing PR head — never from `main` — so its commits stack directly onto the PR.
5. After all workers finish, a final table summarizes verdict and worker action per PR.

**Single pass** — there is no reviewer-after-worker re-review. Use `/review <pr>` manually if a second pass is desired.

## Assumptions & Conventions

Swarmkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: Single-Trunk GitHub Flow

By default, all PRs target `main`. Multi-issue runs auto-cut a short-lived `feature/<slug>-<N>` branch from `main` and route the swarm's PRs through it, but the trunk is always `main` — no `develop` intermediary.

Issues close natively via each PR's `Closes #N` footer the moment the PR merges to `main` (directly or via the epic→main squash).

**To bypass the epic cut** (every PR targets `main` directly):

```bash
/swarm --no-epic 12 15 18   # one-shot, no epic branch
/swarm --no-epic            # loop mode, no epic branch
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

Swarmkit **never closes issues explicitly** — closing is left to GitHub. Each PR's body carries a `Closes #N` footer that GitHub honors natively when the PR merges to `main` (whether directly, or via the epic→main squash). No manual `gh issue close` is required.

## Configuration Notes

- **`swarm`** has `disable-model-invocation: true` — it only runs when you explicitly type `/swarm`, never auto-triggered by Claude. This prevents accidental mass agent spawning.
- **`next-issue`** and **`clean-worktrees`** allow model invocation, so Claude can suggest or invoke them contextually.

## Pairing with Other Plugins

Swarmkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Swarmkit executes work; [speckit](../speckit) defines it. Use them together for the full planning-to-execution loop:

```
/spec add CSV export              # Plan the feature, file issues
/next-issue                       # Confirm what to work on
/swarm                            # Resolve with parallel agents
/clean-worktrees                  # Clean up
```

[Sessionkit](../sessionkit) complements swarmkit throughout: use `/handoff` to preserve state when context runs low mid-swarm, and `/skillit` after a swarm to capture reusable patterns that emerged.

Swarmkit handles parallel-issue resolution — one fire-and-forget agent per GitHub issue, each on its own worktree. For interactive multi-role collaboration with a long-lived team-lead orchestrating architects, builders, reviewers, and testers, use [squadkit](../squadkit).


