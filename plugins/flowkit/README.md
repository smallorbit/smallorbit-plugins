# Flowkit

A Claude Code plugin that manages the full git lifecycle from branch to release. Commit, open PRs, merge, cut release candidates, and ship to main — all from slash commands.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers the plan → execute → ship loop and where flowkit fits in.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install flowkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/flowkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with repo access
- Git configured with push access to your target repos

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **commit** | `/commit` | Stage and commit changes with conventional commit format. Infers logical groupings and writes `type(scope): description` messages. |
| **create-branch** | `/create-branch` | Create a new git branch off `develop` with an inferred or provided name. |
| **cut-epic** | `/cut-epic` | Cut a long-lived `feature/<slug>-<issue>` branch from `develop`, push it, and pin `claude.flowkit.prBase` so subsequent PRs target it. |
| **ship-epic** | `/ship-epic` | Promote a `feature/<slug>-<N>` epic to `develop` via rebase-merge, unset `claude.flowkit.prBase`, delete the epic branch. Closer for `cut-epic`. |
| **open-pr** | `/open-pr` | Push current branch and open a GitHub PR. Respects `claude.flowkit.prBase` for branch targeting. |
| **pr** | `/pr` | Combined: `create-branch` → `commit` → `open-pr` in one step. |
| **merge-pr** | `/merge-pr` | Rebase-merge the open PR for the current branch and delete the remote branch (retargets stacked children; clears blocking swarm worktrees). |
| **restack** | `/restack` | Rebase open descendant PRs of a parent PR onto its updated head and force-push, recursing through the subtree. Use mid-review after revising a stacked PR. |
| **sync** | `/sync` | Checkout `develop`, pull latest, prune stale branches. |
| **cut** | `/cut` | Create a `rc/YYYY-MM-DD.N` release candidate from `develop`. |
| **release** | `/release` | Merge the newest RC to `main`, tag, close issues, clean up RC branches. |
| **ship** | `/ship` | Release closer. Chains `cut → release` to promote `develop` to `main`. Aborts if open `worktree-agent-*` PRs target the resolved base — run `/swarmkit:merge-stack` (and `/ship-epic` when an epic is in flight) first. |
| **pipeline-status** | `/pipeline-status` | Show the full release pipeline: open PRs in flight, `develop` awaiting a cut, RCs awaiting release, and the most recent tag. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **default-branch-prompt** | open-pr | One-time first-run nudge: if the GitHub default branch is `main`, offers to switch it to `develop`. Persists the choice via `claude.flowkit.defaultBranchPrompted`. |
| **git-sync-main** | release | Checkout `main` and pull latest from origin. |
| **pr-base-scope** | swarm | Set/unset `claude.flowkit.prBase` git config for scoped PR targeting. |
| **push-or-pr** | bump-versions, release | Publish commits on a shared branch (`develop`/`main`) safely — branches off, pushes a dated feature branch, opens a PR. Never pushes directly to the checked-out branch. |
| **with-clean-workspace** | merge-pr, release | Auto-stash dirty workspace around implicit post-merge pull via `scripts/with_clean_workspace.sh -- <command ...>`. |

## Typical Workflows

### After a swarm run (canonical bubble-free release)

```
/swarmkit:merge-stack            # land all open worktree-agent-* PRs into the epic (or develop)
# verify on the integrated branch — run your project's typecheck/test/lint
/ship-epic                       # rebase-merge the epic to develop, unset prBase, delete epic branch
/ship                            # cut → release: develop → main
```

The operator-controlled stop between `merge-stack` and `ship-epic` is where the verify gate runs against the cumulative integrated state. `/ship` itself is the release closer only — it refuses to run while open `worktree-agent-*` PRs target the resolved base, pointing the operator back at `merge-stack`.

### Standard release (no swarm)

```
/ship                            # cut → release: develop → main
```

Or run the underlying steps directly:

```
/cut                             # cut a release candidate from develop
/release                         # ship to main, tag, close issues
```

### Pre-flight check

```
/pipeline-status                 # see open PRs, develop, RCs, and last release at a glance
```

### Epic flow (long-lived feature branch)

When a feature spans multiple PRs and needs to stay isolated from `develop` until ready to ship, cut an epic branch and let sub-PRs target it instead of `develop`.

```
/cut-epic 1264                   # creates feature/<slug>-1264 from develop, pins claude.flowkit.prBase
# ... loop ...
/pr add CSV exporter             # sub-PR opened against feature/<slug>-1264 (not develop)
/pr wire exporter into UI        # next sub-PR, also targets the epic branch
# When ready to ship:
/ship-epic                       # rebase-merge to develop, unset prBase, delete epic branch
```

The epic branch composes with `swarmkit:swarm`: agents spawned while `claude.flowkit.prBase` is set will open PRs against the epic branch automatically. Use `swarmkit:merge-stack` to fan the child PRs into the epic, then open the final epic-to-`develop` PR for review.

To verify the integrated state of an epic locally before promotion, check out the feature branch and run your project's verify commands directly — after `swarmkit:merge-stack` lands every sub-PR onto the feature branch, the branch HEAD already is the integrated state, so no synthesis step is needed.

> `/ship` is a develop→main release closer; it does not promote epics. From an epic in flight, run `/swarmkit:merge-stack`, verify on the integrated feature branch, run `/ship-epic` to rebase-merge the epic into `develop`, then run `/ship`. `/ship` aborts if any open `worktree-agent-*` PRs still target the resolved base — that abort is what makes the verify gate between `merge-stack` and `ship-epic` mandatory in practice.

### Mid-review restack

After pushing new commits to a parent PR in a stack, bring every still-open descendant PR up to date in one command:

```
/restack --pr <N>       # rebase all open descendants of PR N and force-push
/restack                # auto-resolve the PR for the current branch
```

The subtree is walked breadth-first: siblings continue independently if one branch hits a conflict. Conflicted branches are reported; the operator resolves by hand and re-runs `/restack`.

### Feature flow

```
/create-branch feat/my-feature   # branch off develop
# ... make changes ...
/commit                          # stage + commit with conventional format
/open-pr                         # push + open PR targeting develop
/merge-pr                        # rebase-merge, delete remote branch
/sync                            # pull develop, prune branches
/cut                             # create rc/2026-04-16.1
/release                         # promote to main, tag v2026.4.16, close issues
```

## Ship boundaries

`/ship` is the release closer only: it chains `cut → release` to promote `develop` to `main`. It does not merge open swarm PRs (`/swarmkit:merge-stack`) and does not promote epics (`/ship-epic`). Operator runs those beforehand so a verify gate sits between integration and release — `/ship` aborts if any open `worktree-agent-*` PRs still target the resolved base. If any step fails, `/ship` stops before the next step; state is left recoverable for re-run.

## Configuration

Flowkit reads one repo-local git config key:

| Key | Purpose | Default |
|-----|---------|---------|
| `claude.flowkit.prBase` | Target base branch for `/open-pr` when no override is passed. Set automatically by `/cut-epic`, `/swarm` (loop mode), and `squadkit:spawn-team --epic`; unset by `/ship-epic`. | `develop` |

Inspect or set manually:

```bash
# Show the effective setting (empty = falls through to default)
git config claude.flowkit.prBase

# Pin PRs to a non-default base for the current repo
git config claude.flowkit.prBase main

# Revert to the default
git config --unset claude.flowkit.prBase
```

### Release scope grouping

`/release` groups `### Release notes` bullets by conventional-commit scope. By default, scopes are auto-detected from the commit range being released — `/release` extracts the `type(scope):` tokens from `git log origin/main..origin/$SOURCE`, normalizes sub-scopes (`flowkit:open-pr` → `flowkit`), and uses the deduplicated set. No configuration needed; it adapts to whatever scopes the repo actually uses.

To pin an explicit scope list (e.g. to enforce naming, exclude noisy one-off scopes, or guarantee a stable rendering order), drop a `.flowkit/scopes.txt` file at the repo root:

```
# .flowkit/scopes.txt — one scope per line, blank lines and # comments ignored
cmdk
cache
library
visualizer
providers
queue
```

When the file is present, `/release` uses it verbatim and skips auto-detection. Use the same token you put in commit messages and PR titles.

> **Migrating from `claude.prBase`?** The unscoped legacy key is no longer read (removed in [#896](https://github.com/smallorbit/smallorbit-plugins/issues/896)). Run `git config --unset claude.prBase && git config claude.flowkit.prBase develop` to move to the scoped key.

## Assumptions & Conventions

Flowkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: `develop` → `main`

Feature work merges into `develop`. Release candidates are cut from `develop`. `main` always reflects what's in production.

### Default Branch

Flowkit works with either GitHub default-branch configuration — `main` (the historical assumption) or `develop` (recommended for new adopters, aligning with modern Gitflow-on-GitHub).

**Why it matters.** GitHub's `Closes #N` keywords only fire when a PR merges into the default branch. With `develop` as default, per-feature PRs close their issues at merge time. With `main` as default, those keywords fire only at release time on the RC→`main` merge. To work safely under either configuration, `/release` runs an explicit `gh issue close` loop after the merge — closing every aggregated issue idempotently regardless of which branch GitHub considers default.

**First-run nudge.** The first time you run `/open-pr` in a repo whose default branch is `main`, flowkit surfaces a one-time prompt offering to switch the default to `develop` (via `gh repo edit --default-branch develop`). Options:

- **Switch to develop** — runs `gh repo edit --default-branch develop` after a second confirmation.
- **Keep main as default** — keeps the current configuration; the prompt won't reappear.
- **Don't ask again** — silences the prompt without recording a deliberate choice.

The choice persists via `claude.flowkit.defaultBranchPrompted`. To re-surface the prompt:

```bash
git config --unset claude.flowkit.defaultBranchPrompted
```

The nudge is **never automatic** — every default-branch change requires explicit user confirmation, and existing `main`-as-default setups continue to work without modification.

### RC Naming: `rc/YYYY-MM-DD.N`

Release candidates are named by date and sequence number (e.g., `rc/2026-04-16.1`). A second cut on the same day becomes `rc/2026-04-16.2`.

### Tag Format: `vYYYY.M.D`

Production releases are tagged with a calendar-versioned tag (e.g., `v2026.4.16`). Multiple releases on the same day append a counter (e.g., `v2026.4.16.1`).

### Commit Format: Conventional Commits

All commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Common types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.

### Issue Lifecycle

`/merge-pr` never closes issues — that's intentional. Issues are closed by `/release` when work actually ships to `main`. This keeps them visible on the board until the feature is in production.

## Pairing with Other Plugins

Flowkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Flowkit handles the shipping half of the development loop. Use it with speckit and swarmkit for the full planning-to-production cycle:

```
/spec add CSV export              # Plan the feature, file issues  (speckit)
/swarm                            # Resolve issues with parallel agents  (swarmkit)
/swarmkit:merge-stack             # Land the swarm PRs into the epic branch
# verify on the epic branch
/ship-epic                        # Promote epic → develop  (flowkit)
/ship                             # cut → release: develop → main  (flowkit)
```

The natural sequence is **speckit → swarmkit → flowkit**: speckit defines the work, swarmkit executes it, flowkit ships it. The operator-controlled stop between `merge-stack` and `ship-epic` is the verify gate against the cumulative integrated state — `/ship` itself refuses to run while swarm PRs are still open against the resolved base. Use [sessionkit](../sessionkit)'s `/handoff` if a release session runs long, and `/skillit` afterwards to capture any new conventions or one-off scripts worth keeping.
