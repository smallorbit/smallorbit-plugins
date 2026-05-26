## MODIFIED Requirements

### Requirement: Feature-Branch Mode
The system SHALL automatically cut a `feature/<slug>-<N>` branch from `origin/main` and pin `claude.flowkit.prBase` to it whenever a run will spawn two or more agents, routing all spawned PRs to the feature branch. The cut is performed inline by swarmkit via `git`/`gh` calls (not delegated to an external skill) so swarmkit owns its own coordination primitive.

#### Scenario: Multi-issue one-shot cuts feature branch
- **WHEN** two or more issue numbers are passed
- **THEN** a `feature/<slug>-<N>` branch is cut from `origin/main` before any agent spawns; all PRs target that branch

#### Scenario: Loop mode cuts feature branch at first non-empty cycle
- **WHEN** loop mode starts with a non-empty board
- **THEN** the feature branch is cut at the start of the first cycle that selects at least one issue

#### Scenario: Single-issue one-shot stays flat
- **WHEN** exactly one issue number is passed
- **THEN** no feature branch is cut; the PR targets `$BASE` directly

#### Scenario: --no-epic suppresses the cut
- **WHEN** `--no-epic` flag is set
- **THEN** no feature branch is cut regardless of agent count; PRs target `$BASE` directly

#### Scenario: --base suppresses the cut
- **WHEN** `--base <branch>` is set
- **THEN** no feature branch is cut; all PRs target `<branch>` directly

#### Scenario: Empty board in loop mode skips cut
- **WHEN** loop mode finds no open issues at entry
- **THEN** the skill announces "Board is clear" and exits without cutting any branch

#### Scenario: Cross-pin guard prevents silent overwrite
- **WHEN** `claude.flowkit.prBase` is already set to a different `feature/` branch
- **THEN** swarm exits with an error message naming the existing pin and offering `--no-epic` or `--epic <existing-slug>` as escapes

#### Scenario: Idempotent on resume
- **WHEN** the feature branch already exists on origin (e.g. resuming a loop run)
- **THEN** swarm reuses the existing branch and refreshes the pin instead of failing

### Requirement: Bottom-Up Stack Merge
The merge-stack skill SHALL retarget every non-root PR in a multi-PR chain to `$BASE` before merging anything, then merge each chain from root to leaf using a uniform squash-and-delete-branch strategy. Because the underlying merge mode is squash, GitHub's tree-based diff handles already-applied predecessor commits automatically — no per-merge downstream rebase is required.

#### Scenario: Only worktree-agent-* PRs are included
- **WHEN** merge-stack scans for open PRs
- **THEN** only PRs whose head branch starts with `worktree-agent-` are included

#### Scenario: Non-root PRs retargeted before first merge
- **WHEN** a multi-PR chain is present
- **THEN** every non-root PR's base is changed to `$BASE` before any merge runs, preventing GitHub's auto-close cascade

#### Scenario: Independent PRs merge in any order
- **WHEN** a PR's base is already `$BASE` and no other PR is stacked on it
- **THEN** it may merge in any order relative to other independent PRs

#### Scenario: Malformed closing-keyword footer warned before merge
- **WHEN** a PR body contains a space-separated multi-ref footer (e.g. `Closes #A #B`)
- **THEN** a warning is emitted before merge and the merge proceeds without blocking

#### Scenario: Conflict stops chain and blocks dependents
- **WHEN** a merge fails with a content conflict
- **THEN** the chain stops at that PR, all PRs above it in the chain are marked blocked, unrelated chains and independent PRs continue, and the user is directed to resolve and re-run

#### Scenario: No PR found stops cleanly
- **WHEN** no open PRs with `worktree-agent-` head branches exist
- **THEN** merge-stack reports "No open swarm PRs found" and stops
