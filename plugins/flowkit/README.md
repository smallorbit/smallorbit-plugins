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
| **preview-epic** | `/preview-epic` | Build a local preview branch combining every open PR in an epic stack via octopus merge (sequential fallback), then run configurable verify commands to validate the epic end-to-end. |
| **open-pr** | `/open-pr` | Push current branch and open a GitHub PR. Respects `claude.flowkit.prBase` for branch targeting. |
| **pr** | `/pr` | Combined: `create-branch` → `commit` → `open-pr` in one step. |
| **merge-pr** | `/merge-pr` | Squash-merge the open PR for the current branch; labels referenced issues with `merged-to-develop` (skipping any labeled `on-hold`). |
| **sync** | `/sync` | Checkout `develop`, pull latest, prune stale branches. |
| **cut** | `/cut` | Create a `rc/YYYY-MM-DD.N` release candidate from `develop`; auto-stages if a staging branch exists. |
| **stage** | `/stage` | Force-reset the `staging` branch to a release candidate. No-op if staging doesn't exist. |
| **release** | `/release` | Detect staging at runtime, merge to `main`, tag, close issues, clean up RC branches. |
| **ship** | `/ship` | Repo-level skill: `merge-stack` → `cut` → `release`. Run after a swarm to merge everything. |
| **hotfix** | `/hotfix` | Emergency fix: branch off `main`, apply fix, PR to `main`, tag, back-merge to `develop`. |
| **pipeline-status** | `/pipeline-status` | Show the full release pipeline: open PRs in flight, `develop` awaiting a cut, RCs/staging awaiting release, and the most recent tag. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly.

| Skill | Used by | Purpose |
|-------|---------|---------|
| **git-sync-main** | release, hotfix | Checkout `main` and pull latest from origin. |
| **git-sync-develop** | sync, release, hotfix | Checkout `develop` and pull latest from origin. |
| **pr-base-scope** | swarm | Set/unset `claude.flowkit.prBase` git config for scoped PR targeting. |

## Typical Workflows

### After a swarm run

```
/ship                            # merge-stack → cut → release
```

### Standard release (no swarm)

```
/cut                             # cut a release candidate from develop
/release                         # ship to main, tag, close issues
```

### Pre-flight check

```
/pipeline-status                 # see open PRs, develop, RCs, and last release at a glance
```

### Emergency hotfix

```
/hotfix fix login redirect       # branch off main, apply fix, ship, back-merge
```

### Epic flow (long-lived feature branch)

When a feature spans multiple PRs and needs to stay isolated from `develop` until ready to ship, cut an epic branch and let sub-PRs target it instead of `develop`.

```
/cut-epic 1264                   # creates feature/<slug>-1264 from develop, pins claude.flowkit.prBase
# ... loop ...
/pr add CSV exporter             # sub-PR opened against feature/<slug>-1264 (not develop)
/pr wire exporter into UI        # next sub-PR, also targets the epic branch
# When ready to ship:
/preview-epic                    # verify the integrated state before promoting
gh pr create --base develop --head feature/<slug>-1264
git config --unset claude.flowkit.prBase
```

The epic branch composes with `swarmkit:swarm`: agents spawned while `claude.flowkit.prBase` is set will open PRs against the epic branch automatically. Use `swarmkit:merge-stack` to fan the child PRs into the epic, then open the final epic-to-`develop` PR for review.

`/preview-epic` validates the integrated state of an epic locally before promotion. Each child PR's CI is green against its own base, but the union may not compile or pass tests — `/preview-epic` catches that integration breakage. It auto-detects the epic model:

- **Stacked PRs** — every PR stays open and chains base→head→base. The skill builds a throwaway preview branch by octopus-merging all heads (sequential fallback on conflict), then runs `verify.typecheck`, `verify.test`, and `verify.lint` from `.squadkit/config.json` against the combined tree. Run before `swarmkit:merge-stack`.
- **Direct-merge-to-epic** — child PRs squash-merge into the long-lived epic branch and close. The epic HEAD already is the integrated state, so verify runs directly on it. Run before opening the final epic-to-`develop` PR.

Nothing is pushed and the epic branch is fetched read-only. See `/preview-epic` for the full Model A vs. Model B detection rules.

> Do not run `/ship` while an epic is in flight unless you intend to ship the epic. `/ship` will rescope `claude.flowkit.prBase` to `develop` for its own flow.

### Feature flow

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

## Ship boundaries

`/ship` only handles the merge-cut-release cascade. Branch creation, commits, and PR opening live in `/pr` and `/swarm`. If `merge-stack` hits a conflict, `/ship` stops before cutting or releasing.

## How Runtime Staging Detection Works

`/cut`, `/stage`, `/release`, `/pipeline-status`, and `/hotfix` all check at runtime whether `origin/staging` exists. No configuration is required — branch presence is the sole signal.

- **Staging exists**: `/cut` pushes the RC to `staging`. `/release` merges `staging` → `main`.
- **Staging absent**: the RC merges directly to `main` without a staging step.

To add a staging environment:

```bash
git checkout -b staging main && git push -u origin staging
```

From that point on, all release skills pick it up automatically.

## Configuration

Flowkit reads one repo-local git config key:

| Key | Purpose | Default |
|-----|---------|---------|
| `claude.flowkit.prBase` | Target base branch for `/open-pr` when no override is passed. Set automatically by `/ship`, `/swarm` loop mode, and `/cut-epic`; unset on teardown. | `develop` |

Inspect or set manually:

```bash
# Show the effective setting (empty = falls through to default)
git config claude.flowkit.prBase

# Pin PRs to a non-default base for the current repo
git config claude.flowkit.prBase main

# Revert to the default
git config --unset claude.flowkit.prBase
```

### Migrating from `claude.prBase`

The legacy key `claude.prBase` is still read as a fallback so existing setups don't break. When flowkit falls back to the legacy key, it emits a one-line deprecation notice with the exact commands below. Migrate at your convenience:

```bash
# Read whatever was set on the legacy key
LEGACY=$(git config claude.prBase)

# Remove the legacy key and write the new one
git config --unset claude.prBase
git config claude.flowkit.prBase "$LEGACY"
```

The legacy fallback is a soft deprecation and will be kept indefinitely — no hard break is planned. The new key aligns with the `claude.<plugin>.<key>` convention used across smallorbit plugins.

## Assumptions & Conventions

Flowkit is opinionated. Understanding these assumptions upfront will save you friction.

### Branching Model: `develop` → `main` (with optional staging)

Feature work merges into `develop`. Release candidates are cut from `develop`. Staging (if present) is an intermediate promotion gate. `main` always reflects what's in production.

### RC Naming: `rc/YYYY-MM-DD.N`

Release candidates are named by date and sequence number (e.g., `rc/2026-04-16.1`). A second cut on the same day becomes `rc/2026-04-16.2`.

### Tag Format: `vYYYY.M.D`

Production releases are tagged with a calendar-versioned tag (e.g., `v2026.4.16`). Multiple releases on the same day append a counter (e.g., `v2026.4.16-2`).

### Hotfix Tags

First hotfix on 2026-04-16: tag `v2026.4.16` + companion `hotfix/v2026.4.16`. A second hotfix the same day: `v2026.4.16.1` + companion `hotfix/v2026.4.16.1`.

The `.N` suffix keeps hotfixes sorting alongside scheduled releases in the tag history. The companion `hotfix/` tag makes them discoverable via `git tag -n` and `git tag --list 'hotfix/*'`.

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
/ship                             # Merge stack → cut → release  (flowkit)
```

The natural sequence is **speckit → swarmkit → flowkit**: speckit defines the work, swarmkit executes it, flowkit ships it. Use [sessionkit](../sessionkit)'s `/handoff` if a release session runs long, and `/skillit` afterwards to capture any new conventions or one-off scripts worth keeping.
