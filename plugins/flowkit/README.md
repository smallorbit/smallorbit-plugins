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
| **merge-pr** | `/merge-pr` | Squash-merge the open PR for the current branch and delete the remote branch. Takes an optional PR number; auto-detects from the current branch when omitted. A numeric PR number is the *only* accepted argument — there is no merge-mode override, and `--merge` / `--rebase` exit 2 as invalid arguments rather than switching strategy. |
| **ship** | `/ship` | Tag HEAD of `main`, push the tag, and create a GitHub Release. Derives the next release tag — today's date for calver repos, semver from conventional commits otherwise. |
| **sync** | `/sync` | Checkout `main`, pull latest, prune stale branches. |
| **pipeline-status** | `/pipeline-status` | Show open PRs targeting `main` and the most recent release tag. |
| **migrate-v4** | `/migrate-v4` | Migrate a v3 repo (develop/RC/main) to single-trunk GitHub Flow. Interactive, with per-step confirmation. Idempotent. |

### Sub-Skills (internal)

| Skill | Used by | Purpose |
|-------|---------|---------|
| **git-sync-main** | none — standalone helper | Checkout `main` and pull latest from origin. |
| **push-or-pr** | bump-versions | Publish commits on a shared branch safely — branches off, pushes, opens a PR. Never pushes directly to the checked-out branch. Callers pass `--prefix` (feature-branch prefix; the script appends `-YYYY-MM-DD`), `--title`, `--body`, and optional `--base` (default `main`) — the first three are required only when there are pending commits, otherwise the run is a no-op. |
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

`/ship` derives the next release tag from the newest `v*` tag — today's date for calver repos, a semver bump from conventional commits otherwise — confirms with the operator, then creates an annotated tag and a GitHub Release with auto-generated notes.

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

1. **Preflight**: five hard conditions — must be on `main`, in sync with origin, workspace clean, at least one commit since the last `v*` tag, and no open `worktree-agent-*` PRs targeting `main` (the one condition with no override — see "After a swarm run" above). Refuses on v3-configured repos (develops-default); direct those to `/migrate-v4`.
2. **Tag derivation**: reads the newest `v*` tag and picks the scheme. Calver-shaped (`vYYYY.M.D[.N]`) → the next tag is today's date, with a `.N` suffix when a tag for today already exists; the conventional-commit signal is ignored. Otherwise semver → scans `git log` since the last `v*` tag: any `BREAKING CHANGE` or `!:` → major, any `feat` → minor, else patch. First release (no `v*` tag at all) defaults to `v0.1.0`.
3. **Operator confirmation**: shows the proposed tag + rationale and waits.
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

### Release tags: calver or semver

`/ship` reads the newest `v*` tag to pick the scheme. Calver-shaped repos (`vYYYY.M.D[.N]`, e.g. `v2026.5.29`) get today's date, with a `.N` same-day suffix when a tag for today already exists. Otherwise the next tag is semver derived from conventional commits, starting at `v0.1.0` when no `v*` tag exists at all.

> **On calver tags?** No migration needed. `/ship` reads existing calver tags and keeps incrementing them — the conventional-commit derivation only applies to `vMAJOR.MINOR.PATCH` shaped tags.

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
