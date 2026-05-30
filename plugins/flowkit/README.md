# Flowkit

A Claude Code plugin that manages the full git lifecycle from commit to release. Commit, open PRs, merge, and ship to main — all from slash commands. Flowkit v4 uses single-trunk [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow): feature branches → squash-merge to `main` → tag for release.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers the plan → execute → ship loop and where flowkit fits in.
>
> **Upgrading from v3?** See [MIGRATION-v4.md](./MIGRATION-v4.md) for the automated migration helper and manual steps.

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
| **commit** | `/commit` | Stage and commit changes — infers `type(scope): description` from the staged diff. |
| **pr** | `/pr` | One-shot: commit if dirty, then push and open a PR against `main` (or `claude.flowkit.prBase` when set). |
| **open-pr** | `/open-pr` | Push current branch and open a PR. Base resolution: `--base` → `claude.flowkit.prBase` → `main`. |
| **merge-pr** | `/merge-pr` | Squash-merge the open PR for the current branch and delete the remote branch. |
| **ship** | `/ship` | Tag HEAD of `main`, push the tag, and create a GitHub Release. Derives the next semver from conventional commits since the last `v*` tag. |
| **sync** | `/sync` | Checkout `main`, pull latest, prune stale branches. |
| **pipeline-status** | `/pipeline-status` | Show open PRs targeting `main` and the most recent release tag. |
| **migrate-v4** | `/migrate-v4` | Migrate a v3 repo (develop/RC/main) to single-trunk GitHub Flow. Interactive, with per-step confirmation. Idempotent. |

### Sub-Skills (internal)

| Skill | Used by | Purpose |
|-------|---------|---------|
| **git-sync-main** | internal | Checkout `main` and pull latest from origin. |
| **push-or-pr** | bump-versions | Publish commits on a shared branch safely — branches off, pushes, opens a PR. Never pushes directly to the checked-out branch. |
| **with-clean-workspace** | merge-pr | Auto-stash dirty workspace around implicit post-merge pulls. |

## Typical Workflows

### After a swarm run

```
/swarmkit:merge-stack            # land all open worktree-agent-* PRs into main
# verify on main — run your project's typecheck/test/lint
/ship                            # tag HEAD of main, create GitHub Release
```

`/ship` refuses to run while open `worktree-agent-*` PRs target `main` — that's the mechanism that makes the verify gate mandatory.

### Standard release (no swarm)

```
/ship
```

`/ship` derives the next semver from conventional commits since the last `v*` tag, confirms with the operator, then creates an annotated tag and a GitHub Release with auto-generated notes.

### Pre-flight check

```
/pipeline-status                 # see open PRs and last release tag at a glance
```

### Feature flow

```
# ... make changes on a feature branch ...
/commit                          # stage + commit with conventional format
/open-pr                         # push + open PR targeting main
/merge-pr                        # squash-merge, delete remote branch
/sync                            # pull main, prune branches
/ship                            # tag and release
```

### Epic flow (long-lived feature branch)

For work spanning multiple PRs that needs to stay isolated until ready:

```
git checkout -b feature/my-epic-1234     # cut from main
git config claude.flowkit.prBase feature/my-epic-1234
# ... loop: /pr for each sub-feature ...
# When ready:
git config --unset claude.flowkit.prBase
gh pr create --base main                 # epic → main PR
/merge-pr
/ship
```

squadkit's `spawn-team --epic` handles the branch-cut and pin automatically for multi-builder crews.

## Ship

`/ship` is the single release command:

1. **Preflight**: must be on `main`, in sync with origin, workspace clean, at least one commit since the last `v*` tag. Refuses on v3-configured repos (develops-default); direct those to `/migrate-v4`.
2. **Semver derivation**: scans `git log` since the last `v*` tag. Any `BREAKING CHANGE` or `!:` → major. Any `feat` → minor. Else → patch. First release (no prior `v*` tag) defaults to `v0.1.0`.
3. **Operator confirmation**: shows the proposed tag + version bump type and waits.
4. **Tag + release**: creates an annotated tag, pushes it, runs `gh release create --generate-notes`.

## Configuration

| Key | Purpose | Default |
|-----|---------|---------|
| `claude.flowkit.prBase` | Target base branch for `/open-pr` when no `--base` override is passed. Set by `squadkit:spawn-team --epic`; unset after the epic merges. | `main` |

```bash
# Inspect
git config claude.flowkit.prBase

# Pin to an epic branch
git config claude.flowkit.prBase feature/my-epic-1234

# Revert
git config --unset claude.flowkit.prBase
```

## Conventions

### Branching model: single-trunk on `main`

Feature branches merge into `main` via squash. `main` always reflects the latest shipped state. No `develop`, no `rc/*` branches.

### Semver tags: `vMAJOR.MINOR.PATCH`

Flowkit v4 uses conventional semver derived from the commit log. The first release defaults to `v0.1.0`.

> **Migrating from calver tags?** `/ship`'s first-ever run in a repo with no existing `v*` tags starts at `v0.1.0`. If you have calver tags like `v2026.5.29`, `/ship` will read them and use the next calver increment — the derivation only applies to `vMAJOR.MINOR.PATCH` shaped tags. Calver repos are fine without migration.

### Commit format: Conventional Commits

All commits follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Common types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`.

## Pairing with Other Plugins

Flowkit handles the shipping half of the development loop. Use it with speckit and swarmkit for the full planning-to-production cycle:

```
/spec add CSV export              # Plan the feature, file issues  (speckit)
/swarm                            # Resolve issues with parallel agents  (swarmkit)
/swarmkit:merge-stack             # Land the swarm PRs into main
# verify on main
/ship                             # tag HEAD of main, create GitHub Release  (flowkit)
```

The natural sequence is **speckit → swarmkit → flowkit**: speckit defines the work, swarmkit executes it, flowkit ships it. Use [sessionkit](../sessionkit)'s `/handoff` if a release session runs long, and `/skillit` afterwards to capture any new conventions or one-off scripts worth keeping.
