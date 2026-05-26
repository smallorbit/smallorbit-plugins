## MODIFIED Requirements

### Requirement: Main Repo Root and Base Branch Resolution
The system SHALL resolve the main repository root via `git rev-parse --git-common-dir` and read `baseBranch` from `<repo-root>/.squadkit/config.json`, defaulting to `main` only when the file or key is missing, and SHALL NOT hardcode `main` elsewhere.

#### Scenario: Worktree caller resolves to main root
- **WHEN** invoked from a linked worktree
- **THEN** `REPO_ROOT` resolves to the main repo root via the shared `.git` directory

#### Scenario: Missing config defaults to main
- **WHEN** `.squadkit/config.json` is absent or has no `baseBranch` key
- **THEN** `BASE_BRANCH` resolves to `main`

#### Scenario: Configured baseBranch wins
- **WHEN** `.squadkit/config.json` records a `baseBranch`
- **THEN** that value is used everywhere `${BASE_BRANCH}` is referenced

### Requirement: Epic Branch Cutting and Cross-Pin Guard
The system SHALL cut `feature/<slug>-<issue>` from `origin/main` via inline `git`/`gh` calls when `--epic` is provided or chosen, SHALL refuse to proceed when an incompatible epic is already pinned, and SHALL default the prompt toward cutting an epic when the resolved roster will produce three or more child PRs. squadkit owns the epic-cutting primitive — it does not delegate to an external skill.

#### Scenario: Existing pin matches reuses silently
- **WHEN** `claude.flowkit.prBase` is already pinned to `feature/<slug>-<issue>` matching the requested slug
- **THEN** the skill proceeds silently and the existing branch is reused idempotently

#### Scenario: Conflicting pin blocks the spawn
- **WHEN** `claude.flowkit.prBase` is already pinned to a different `feature/...` branch
- **THEN** the skill exits with operator guidance to clear the pin or re-run with `--epic` matching the pinned slug

#### Scenario: Multi-builder defaults to cut-epic
- **WHEN** the resolved roster has more than one builder and no `--epic` was supplied
- **THEN** the prompt biases toward `Cut epic` and `Use ${BASE_BRANCH}` is accepted only after explicit confirmation that the work is a single PR

#### Scenario: Branch reused when it already exists on origin
- **WHEN** the resolved `feature/<slug>-<issue>` branch exists on origin
- **THEN** it is fetched and checked out rather than recreated; the pin is refreshed

#### Scenario: Branch always cut from origin/main
- **WHEN** the epic branch is created fresh
- **THEN** it is created from `origin/main`, not from a local stale branch or any other base
