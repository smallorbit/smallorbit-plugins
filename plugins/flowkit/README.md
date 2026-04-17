# Flowkit

A Claude Code plugin that manages the full git lifecycle from branch to release. Commit, open PRs, merge, cut release candidates, and ship to main — all from slash commands.

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
| **open-pr** | `/open-pr` | Push current branch and open a GitHub PR. Respects `claude.prBase` for branch targeting. |
| **pr** | `/pr` | Combined: `create-branch` → `commit` → `open-pr` in one step. |
| **merge-pr** | `/merge-pr` | Squash-merge the open PR for the current branch; labels referenced issues with `merged-to-develop`. |
| **sync** | `/sync` | Checkout `develop`, pull latest, prune stale branches. |
| **cut** | `/cut` | Create a `rc/YYYY-MM-DD.N` release candidate from `develop`; auto-stages if a staging branch exists. |
| **stage** | `/stage` | Force-reset the `staging` branch to a release candidate. No-op if staging doesn't exist. |
| **release** | `/release` | Detect staging at runtime, merge to `main`, tag, close issues, clean up RC branches. |
| **ship** | `/ship` | Full one-shot cycle: `pr` → `merge-pr` → `sync` → `cut` → `release`. |
| **hotfix** | `/hotfix` | Emergency fix: branch off `main`, apply fix, PR to `main`, tag, back-merge to `develop`. |
| **release-status** | `/release-status` | Show what's in staging awaiting release and what's in `develop` awaiting a cut. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **git-sync-main** | release, hotfix | Checkout `main` and pull latest from origin. |
| **git-sync-develop** | sync, release, hotfix | Checkout `develop` and pull latest from origin. |
| **gh-close-referenced-issues** | release, hotfix | Parse merged PR bodies; close referenced issues and resolved epics. |
| **pr-base-scope** | ship, swarm | Set/unset `claude.prBase` git config for scoped PR targeting. |

## Typical Workflows

```
# Standard release from develop
/cut                             # cut a release candidate from develop
/release                         # ship to main, tag, close issues

# Full one-command ship cycle
/ship                            # branch → commit → PR → merge → cut → release

# Check before acting
/release-status                  # see what's staging vs. what's in develop

# Emergency hotfix
/hotfix fix login redirect       # branch off main, apply fix, ship, back-merge
```

Step-by-step feature flow:

```
/create-branch feat/my-feature   # branch off develop
# ... make changes ...
/commit                          # stage + commit with conventional format
/open-pr                         # push + open PR targeting develop
/merge-pr                        # squash-merge, label issues
/sync                            # pull develop, prune branches
/cut                             # create rc/2026-04-16.1, auto-stage if staging exists
/release                         # promote to main, tag v2026.4.16, close issues
```

## How Ship Works

`/ship` runs the full pipeline in a single command: it creates a branch, commits staged changes, opens a PR, squash-merges it, syncs `develop`, cuts a release candidate, and promotes it to `main`.

The pipeline is scoped with `claude.prBase`: before spawning sub-agents, `/ship` (and `/swarm`) set this config so every PR in the run targets the correct base branch. It is unset when the run completes.

Self-review is intentionally excluded from `/ship`. The command is a release pipeline, not a quality gate — code review happens before merge, not during ship.

## How Runtime Staging Detection Works

`/cut`, `/stage`, `/release`, `/release-status`, and `/hotfix` all check at runtime whether `origin/staging` exists. No configuration is required — branch presence is the sole signal.

- **Staging exists**: `/cut` pushes the RC to `staging`. `/release` merges `staging` → `main`.
- **Staging absent**: the RC merges directly to `main` without a staging step.

To add a staging environment:

```bash
git checkout -b staging main && git push -u origin staging
```

From that point on, all release skills pick it up automatically.

## Assumptions & Conventions

Flowkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: `develop` → `main` (with optional staging)

Feature work lands in `develop`. Release candidates are cut from `develop`. Staging (if present) is an intermediate promotion gate. `main` always reflects what's in production.

### RC Naming: `rc/YYYY-MM-DD.N`

Release candidates are named by date and sequence number (e.g., `rc/2026-04-16.1`). A second cut on the same day becomes `rc/2026-04-16.2`.

### Tag Format: `vYYYY.M.D`

Production releases are tagged with a calendar-versioned tag (e.g., `v2026.4.16`). Multiple releases on the same day append a counter (e.g., `v2026.4.16-2`).

### Hotfix Tags: `vYYYY.M.D-hotfix`

Hotfixes are tagged separately (e.g., `v2026.4.16-hotfix`) to distinguish them from scheduled releases and preserve the release history.

### Commit Format: Conventional Commits

All commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Common types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.

### Issue Lifecycle

`/merge-pr` never closes issues — that's intentional. Issues are closed by `/release` (or `/hotfix`) when work actually ships to `main`. This keeps them visible on the board until the feature is in production.

## Pairing with Other Plugins

Flowkit handles the shipping half of the development loop. Use it with speckit and swarmkit for the full planning-to-production cycle:

```
/spec add CSV export              # Plan the feature, file issues  (speckit)
/swarm                            # Resolve issues with parallel agents  (swarmkit)
/cut                              # Cut a release candidate  (flowkit)
/release                          # Ship to main  (flowkit)
```

The natural sequence is **speckit → swarmkit → flowkit**: speckit defines the work, swarmkit executes it, flowkit ships it. Use [sessionkit](../sessionkit)'s `/handoff` if a release session runs long, and `/skillit` afterwards to capture any new conventions or one-off scripts worth keeping.
