## ADDED Requirements

### Requirement: LLM-Derived Commit Messages
The `commit` skill SHALL derive the conventional-commit type, scope, and subject from the staged diff in the current turn without an operator interview. The operator may edit the proposed message before commit, but is not prompted for type/scope/subject inputs.

#### Scenario: Type inferred from change shape
- **WHEN** the staged diff is read
- **THEN** the type is selected from the staged content (e.g. new files / new behavior → `feat`, bug-fix patterns → `fix`, doc-only edits → `docs`, refactors → `refactor`)

#### Scenario: Scope inferred from changed paths
- **WHEN** the staged diff touches files under a single conventional scope (e.g. `plugins/flowkit/skills/x/...`)
- **THEN** the scope is set accordingly (e.g. `flowkit:x` or `flowkit`)

#### Scenario: Multi-scope changes pick the dominant scope
- **WHEN** the staged diff spans multiple plausible scopes
- **THEN** the dominant scope (most lines changed, or the most semantically central) is selected; cross-cutting scopes are noted in the body rather than the subject

#### Scenario: Logical groupings split into multiple commits
- **WHEN** the workspace diff contains multiple unrelated concerns
- **THEN** the changes are split into one commit per logical concern, each with its own conventional-format message

### Requirement: Main Sync
The sync skill SHALL check out `main`, pull the latest from origin, prune stale remote-tracking refs, and delete every local branch already merged into `main` (excluding `main` and the current branch).

#### Scenario: main checked out and pulled first
- **WHEN** sync runs
- **THEN** the first action is `git checkout main && git pull origin main`

#### Scenario: Stale remote refs pruned
- **WHEN** sync runs
- **THEN** `git fetch --prune` is invoked to drop stale remote-tracking refs

#### Scenario: Merged local branches deleted
- **WHEN** local branches are fully merged into `main`
- **THEN** they are deleted, excluding `main` and the current branch

### Requirement: Ship
The `/flowkit:ship` skill SHALL preflight, derive the next semver from conventional commits since the last `v*` tag, show the proposed tag to the operator for confirmation, tag HEAD of `main` (annotated), push the tag, and create a GitHub Release with an auto-generated changelog. No release branch, no release PR.

#### Scenario: Preflight requires main, sync, clean, and progress
- **WHEN** ship runs
- **THEN** it refuses unless: current branch is `main`, local `main` is in sync with `origin/main`, the working tree is clean, and at least one commit exists since the last `v*` tag

#### Scenario: Semver derived from conventional commits
- **WHEN** computing the next tag
- **THEN** the bump type is the highest signal across commits since the last tag: any `BREAKING CHANGE` or `!:` → major; any `feat` → minor; otherwise → patch

#### Scenario: Operator confirms proposed tag before push
- **WHEN** the next tag is computed
- **THEN** it is shown to the operator with the bump rationale and the operator confirms (or overrides) before any push

#### Scenario: Annotated tag pushed
- **WHEN** the tag is created
- **THEN** it is an annotated tag (`git tag -a`) and is pushed to origin

#### Scenario: GitHub Release created with auto-changelog
- **WHEN** the tag is pushed
- **THEN** `gh release create` is invoked with `--generate-notes` (or equivalent), producing a release page listing the commits/PRs since the previous tag

#### Scenario: First ever release skips the "commits since last tag" gate
- **WHEN** no prior `v*` tag exists
- **THEN** the gate is treated as satisfied (any commit on main qualifies) and the next tag defaults to `v0.1.0`

### Requirement: V3-to-V4 Migration Helper
The `/flowkit:migrate-v4` skill SHALL detect whether the current repository is set up for the legacy develop/RC/main flow, present an interactive migration plan, and execute the plan step by step with operator confirmation at each mutation. The skill SHALL be idempotent — re-running on an already-migrated repo SHALL report "nothing to do" and exit cleanly.

#### Scenario: Legacy state detected
- **WHEN** the repository has any of: GitHub default branch set to `develop`, `develop` branch on origin without a `main` branch, a `claude.flowkit.defaultBranchPrompted` config key, or any `rc/*` branch on origin
- **THEN** the migration plan covers the matching steps (FF `main` to `develop`, switch default branch to `main`, delete `develop`, clean RC branches, unset legacy config keys)

#### Scenario: Plan presented before any mutation
- **WHEN** the helper has detected migration steps
- **THEN** the operator sees the full plan and confirms (or aborts) before any branch, default-branch, or config mutation runs

#### Scenario: Step-by-step confirmation
- **WHEN** the migration runs
- **THEN** each destructive step (default-branch switch, `develop` deletion, RC branch deletion) prompts for confirmation; the operator can skip any step or abort the run

#### Scenario: Idempotent on migrated repo
- **WHEN** the repo is already fully on `main` with no legacy artifacts
- **THEN** the helper reports "nothing to do" and exits zero without any mutation

#### Scenario: Leftover feature branches surfaced, not deleted
- **WHEN** legacy `feature/<slug>-<N>` branches exist on origin
- **THEN** they are listed in the migration plan with operator guidance to finish or delete them manually; the helper SHALL NOT auto-delete feature branches (they may contain unfinished work)

### Requirement: Preflight Migration Check
Skills that mutate repository state under the v4 model — at minimum `/flowkit:ship` and `/flowkit:pr` — SHALL detect legacy v3 setup at preflight and refuse to run, directing the operator to `/flowkit:migrate-v4`.

#### Scenario: Develop-default repo blocks ship
- **WHEN** `/flowkit:ship` runs and the GitHub default branch is `develop` (or `develop` exists on origin while `main` does not)
- **THEN** ship exits non-zero with a single-line directive: "This repo is set up for flowkit v3 (develop/main split). Run `/flowkit:migrate-v4` to migrate to single-trunk before using v4 skills."

#### Scenario: Develop-default repo blocks pr
- **WHEN** `/flowkit:pr` runs and the GitHub default branch is `develop` (or `develop` exists on origin while `main` does not)
- **THEN** pr exits non-zero with the same directive as ship

#### Scenario: Already-migrated repo proceeds silently
- **WHEN** the preflight check finds no legacy artifacts
- **THEN** no message is emitted and the skill proceeds with its normal preflight

## MODIFIED Requirements

### Requirement: Base Branch Resolution
Every skill that opens a PR SHALL resolve the base branch via a deterministic three-step chain: explicit `--base` arg → `claude.flowkit.prBase` config key → `main`. The resolved base SHALL be non-empty and SHALL NOT equal the current HEAD.

#### Scenario: Explicit --base flag wins
- **WHEN** `$ARGUMENTS` contains a `--base <branch>` token
- **THEN** that branch is used and later resolution steps are skipped

#### Scenario: Config key consulted after explicit arg
- **WHEN** no `--base` arg is provided and `claude.flowkit.prBase` is set
- **THEN** the config value is used

#### Scenario: Default to main
- **WHEN** no `--base` arg and no config key
- **THEN** `main` is used

#### Scenario: Self-targeting guard rejects pin pointing at current branch
- **WHEN** the resolved base equals the current HEAD branch
- **THEN** the skill exits non-zero with operator guidance to override with `--base` or unset the pin

### Requirement: Conventional Commit Format
All commits authored by the system SHALL follow the format `type(scope): description` with a subject line under 72 characters and one of the recognized type tokens: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`. Breaking changes SHALL be marked with `!` after the type or `BREAKING CHANGE` in the body so the release skill can derive the next semver bump.

#### Scenario: Subject under 72 characters
- **WHEN** a commit message is written
- **THEN** the subject line is 72 characters or fewer

#### Scenario: Nothing to commit reported cleanly
- **WHEN** `git status` is clean
- **THEN** the skill reports "Nothing to commit" and stops

#### Scenario: HEREDOC syntax used for multi-line messages
- **WHEN** a commit message has a body
- **THEN** it is composed via HEREDOC so newlines are preserved

#### Scenario: Amend never used
- **WHEN** new commits are created
- **THEN** they are new commits, never an amend of a previous commit

#### Scenario: Breaking change marker recognized
- **WHEN** a commit introduces a breaking change
- **THEN** the message carries either `!` after the type (e.g. `feat!: drop legacy flag`) or a `BREAKING CHANGE:` token in the body

### Requirement: PR Body Standard
Every PR opened by the system SHALL emit a body with three sections in order — `## Summary` (1–3 sentence narrative), `## Changes` (bulleted concrete edits), `## Test plan` (`- [ ]` checklist) — followed by an issue-reference footer with one closing-keyword token per line.

#### Scenario: Three sections in order
- **WHEN** a PR body is assembled
- **THEN** it contains `## Summary`, `## Changes`, and `## Test plan` headings in that order

#### Scenario: Closing-keyword tokens one per line
- **WHEN** the footer references multiple issues
- **THEN** each `Closes #N` / `Refs #N` token appears on its own line

#### Scenario: Broken multi-ref footer rejected
- **WHEN** the assembled body contains a space-separated multi-ref form (e.g. `Closes #1 #2 #3`)
- **THEN** the skill exits non-zero with guidance to rewrite one token per line — it does not auto-rewrite

#### Scenario: Verbatim forwarding of author-committed keywords
- **WHEN** issue-ref tokens are extracted from commit messages on the branch
- **THEN** they are emitted in the footer verbatim, preserving the author's original casing and keyword choice (`Fixes`/`Resolves`/`Closes`)

### Requirement: Open PR
The system SHALL push the current branch to origin with `-u`, refuse to open a PR from a protected branch (`main`, `master`), resolve `$BASE` via the canonical chain, assemble the canonical body, and call `gh pr create --base "$BASE"` with the body. Force-push SHALL NOT be used.

#### Scenario: Protected branch blocked
- **WHEN** the current branch is `main` or `master`
- **THEN** the skill stops with an error directing the operator to check out a feature branch

#### Scenario: Branch pushed with -u, not force-pushed
- **WHEN** the current branch is pushed
- **THEN** the command used is `git push -u origin HEAD` without `--force` or `--force-with-lease`

### Requirement: PR Lifecycle Orchestrator
The `/pr` skill SHALL chain `commit` (if there are uncommitted changes) → `open-pr` in sequence, stopping on the first sub-skill failure.

#### Scenario: Commit skipped on clean workspace
- **WHEN** the workspace has no changes
- **THEN** `/pr` skips `commit` and proceeds directly to `open-pr`

#### Scenario: Failure aborts the chain
- **WHEN** any sub-skill fails
- **THEN** the chain stops at that step and reports the error; no subsequent step runs

### Requirement: PR Merge
The merge-pr skill SHALL squash-merge the open PR for the current branch (never rebase-merge, never merge-commit), delete the remote branch via `--delete-branch`, and free the local branch when a worktree holds it — auto-checking out the base branch if the main worktree holds the head.

#### Scenario: Squash-merge only
- **WHEN** the merge runs
- **THEN** the call uses `gh pr merge --squash --delete-branch`; never `--rebase` or `--merge`

#### Scenario: Main worktree holding head auto-checks out base
- **WHEN** the head branch is checked out in the main worktree (the canonical post-`push-or-pr` state)
- **THEN** the main worktree is checked out to the base branch so the head branch can be released without manual intervention

#### Scenario: Caller-owned worktree refuses removal
- **WHEN** the head branch is held by a linked worktree containing the caller's cwd
- **THEN** the script refuses with operator guidance to exit the worktree first

#### Scenario: Implicit post-merge pull wrapped against dirty workspace
- **WHEN** the workspace has uncommitted changes at merge time
- **THEN** the merge is wrapped via `with-clean-workspace` so the implicit post-merge pull does not fail with `cannot pull with rebase`

#### Scenario: Issues closed by GitHub at merge time
- **WHEN** a PR with `Closes #N` footers squash-merges into `main`
- **THEN** GitHub auto-closes the referenced issues; the skill does not run an explicit close loop

### Requirement: Shared-Branch Publishing
The push-or-pr skill SHALL never push directly to a shared branch (`main` or any other checked-out branch). When pending commits exist, it SHALL save them on an auto-created dated feature branch, reset the original local branch to its upstream, push the feature branch, and open a PR against `$BASE` (default `main`).

#### Scenario: No-op on clean upstream
- **WHEN** the current branch has no commits ahead of upstream
- **THEN** the script emits `push_result: "noop"` and does nothing

#### Scenario: Pending commits trigger feature-branch detour
- **WHEN** there are pending commits
- **THEN** they are placed on an auto-created branch named `<prefix>-YYYY-MM-DD[<-N>]` and a PR is opened from that branch against `$BASE`

#### Scenario: Original branch reset to upstream
- **WHEN** the detour completes
- **THEN** the local copy of the original branch is reset to its upstream so it no longer holds the unpublished commits

#### Scenario: Missing required PR args rejected
- **WHEN** there are pending commits and any of `--prefix` / `--title` / `--body` is missing
- **THEN** the script exits with code 2 and stderr describing the missing argument

#### Scenario: Tags never pushed
- **WHEN** the script runs
- **THEN** no tag push is performed; tag creation belongs to the caller

### Requirement: Pipeline Status
The pipeline-status skill SHALL be read-only, fetch the latest remote state first, and print all pipeline stages in left-to-right order — in-flight (open PRs → main) and released (most recent `v*` tag) — even when stages are empty, followed by an actionable "Next step" line.

#### Scenario: Read-only behavior
- **WHEN** the skill runs
- **THEN** no branch, tag, PR, or label is mutated

#### Scenario: Fetch precedes any read
- **WHEN** the skill starts
- **THEN** `git fetch origin` runs before any read of remote state

#### Scenario: All stages always printed
- **WHEN** any stage is empty
- **THEN** the stage is still printed with "none" rather than omitted

#### Scenario: Next step priority order
- **WHEN** multiple states could trigger a suggestion
- **THEN** the highest-priority match wins: blockers/conflicts on a PR → resolve those; approved+clean PR → merge it; non-draft unreviewed PRs → review them; commits on main since last tag → run `/flowkit:ship`; otherwise → "Nothing to ship"

#### Scenario: Draft PRs never trigger a review suggestion
- **WHEN** the only unreviewed PRs are drafts
- **THEN** the "review open PRs" suggestion does not fire

## REMOVED Requirements

### Requirement: Default Branch Prompt
**Reason**: Only `main` matters under GitHub Flow — there is no `develop`/`main` split to disambiguate.
**Migration**: Operators run `/flowkit:migrate-v4` once per repo; no per-session default-branch prompt is needed.

### Requirement: Branch Creation
**Reason**: Operators create branches inline; `/pr` handles the common case of "commit + open PR off the current state."
**Migration**: Use `git checkout -b <name>` directly when a branch is needed before `/pr` runs.

### Requirement: Restack Descendants
**Reason**: Squash-merge eliminates the stacked-rebase use case. GitHub's tree-based diff handles already-applied predecessor commits without per-merge downstream rebase.
**Migration**: No replacement needed. After a parent PR merges, descendant PRs continue to apply cleanly against the updated base.

### Requirement: Develop Sync
**Reason**: Replaced by `Main Sync` (under `## ADDED Requirements`) which operates on `main` instead of `develop`.
**Migration**: Continue to invoke `/flowkit:sync`; the skill now syncs `main` rather than `develop`.

### Requirement: Epic Branch Creation
**Reason**: Callers (squadkit, swarmkit) cut feature branches inline via `git`/`gh` calls. flowkit no longer owns an epic-cutting primitive.
**Migration**: See `squadkit-spawn-team` `Epic Branch Cutting and Cross-Pin Guard` and `swarmkit` `Feature-Branch Mode` — they now own their own coordination cuts.

### Requirement: Epic Promotion
**Reason**: No develop/epic-promotion hierarchy in GitHub Flow. Feature branches PR directly into `main` via squash-merge.
**Migration**: Squash-merge each builder PR straight to `main` (or to the epic feature branch when one is in flight via swarmkit/squadkit).

### Requirement: Release Candidate Cut
**Reason**: No RC branches in GitHub Flow. There is no stabilization stage between `develop` and `main` — only PRs into `main`.
**Migration**: `/flowkit:ship` tags HEAD of `main` directly and creates a GitHub Release. No RC branch is involved.

### Requirement: Release to Main
**Reason**: Replaced by single-tag release via `Ship` (under `## ADDED Requirements`). There is no separate "release to main" step because every PR already merges to `main` directly.
**Migration**: Use `/flowkit:ship`.

### Requirement: Ship Closer
**Reason**: Replaced by `Ship` (under `## ADDED Requirements`). The new Ship is conceptually different — it is the *only* release step, not a closer over `cut → release`. There is no `cut` and no `release` to close.
**Migration**: Use `/flowkit:ship`, which preflights, computes semver, tags `main`, and creates the GitHub Release in one command.

### Requirement: PR-Base Scope Set/Unset
**Reason**: Operator manages the `claude.flowkit.prBase` pin directly via `git config` rather than through a dedicated skill — the surface is too thin to justify a skill.
**Migration**: `git config --local claude.flowkit.prBase <branch>` to set; `git config --local --unset claude.flowkit.prBase` to clear.
