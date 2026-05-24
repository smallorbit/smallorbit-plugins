# flowkit

## Purpose

Manage the full git lifecycle from branch creation to production release on a `develop` → `main` workflow. Handle branch creation, conventional-format commits, PR creation/merge/restack, long-lived epic branches, release-candidate cut and release, and release-pipeline visibility — composing into a bubble-free release shape where `main`'s first-parent line is linear and per-feature commits stay visible.

## Requirements

### Requirement: Base Branch Resolution
Every skill that opens a PR SHALL resolve the base branch via a deterministic four-step chain: explicit `--base` arg → `claude.flowkit.prBase` config key → `develop` if present on origin → repo default branch with a stderr warning. The resolved base SHALL be non-empty and SHALL NOT equal the current HEAD.

#### Scenario: Explicit --base flag wins
- **WHEN** `$ARGUMENTS` contains a `--base <branch>` token
- **THEN** that branch is used and later resolution steps are skipped

#### Scenario: Config key consulted after explicit arg
- **WHEN** no `--base` arg is provided and `claude.flowkit.prBase` is set
- **THEN** the config value is used

#### Scenario: develop preferred when on origin
- **WHEN** no `--base` arg and no config key, and `origin/develop` exists
- **THEN** `develop` is used

#### Scenario: Repo default fallback with warning
- **WHEN** no `--base` arg, no config key, and `develop` is not on origin
- **THEN** the GitHub default branch is used and a one-line stderr warning is emitted

#### Scenario: Self-targeting guard rejects pin pointing at current branch
- **WHEN** the resolved base equals the current HEAD branch
- **THEN** the skill exits non-zero with operator guidance to override with `--base` or unset the pin

### Requirement: Default Branch Prompt
The first time `/open-pr` runs in a repository whose GitHub default branch is exactly `main`, the system SHALL present a one-time prompt offering to switch the default to `develop`. The choice SHALL be persisted via `claude.flowkit.defaultBranchPrompted` so the prompt never reappears once decided.

#### Scenario: Marker skips the prompt
- **WHEN** `claude.flowkit.defaultBranchPrompted` is `true`
- **THEN** the sub-skill exits silently and `/open-pr` proceeds

#### Scenario: Non-main default skips the prompt
- **WHEN** the GitHub default branch is anything other than `main` (including unreadable / missing `gh` auth)
- **THEN** the sub-skill exits silently

#### Scenario: Switch requires double confirmation
- **WHEN** the user selects `Switch to develop`
- **THEN** a second confirmation prompt is required before `gh repo edit --default-branch develop` runs

#### Scenario: Successful switch sets the marker
- **WHEN** the switch confirmation succeeds and the `gh repo edit` call returns success
- **THEN** `claude.flowkit.defaultBranchPrompted` is set to `true`

#### Scenario: Cancelled switch keeps marker unset
- **WHEN** the user cancels at the second confirmation
- **THEN** the marker stays unset and the three-option prompt resurfaces on next invocation

#### Scenario: Keep or skip sets the marker without mutation
- **WHEN** the user selects `Keep main as default` or `Don't ask again`
- **THEN** the marker is set to `true` and no repository default-branch change is made

### Requirement: Branch Creation
The system SHALL create new branches off `origin/develop`, infer kebab-case names with appropriate `feat/`, `fix/`, `chore/`, or `docs/` prefixes from a description, and refuse to create the reserved names `main`, `master`, or `develop`.

#### Scenario: Inferred name from description
- **WHEN** `$ARGUMENTS` is a plain English description (e.g. "add user auth")
- **THEN** the branch name is generated as a kebab-case slug with a type-prefix (e.g. `feat/add-user-auth`) and capped at 50 characters

#### Scenario: Explicit branch name used as-is
- **WHEN** `$ARGUMENTS` is already a branch name with a recognized prefix
- **THEN** it is used directly without re-inference

#### Scenario: Reserved names rejected
- **WHEN** the inferred or provided name is `main`, `master`, or `develop`
- **THEN** the skill stops and prompts the user for a different name

#### Scenario: Branch always cut from origin
- **WHEN** the branch is created
- **THEN** it is created from `origin/develop`, never from a local stale `develop`

### Requirement: Conventional Commit Format
All commits authored by the system SHALL follow the format `type(scope): description` with a subject line under 72 characters and one of the recognized type tokens: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`.

#### Scenario: Subject under 72 characters
- **WHEN** a commit message is written
- **THEN** the subject line is 72 characters or fewer

#### Scenario: Logical groupings split into multiple commits
- **WHEN** the workspace diff contains multiple unrelated concerns
- **THEN** the changes are split into one commit per logical concern, each with its own conventional-format message

#### Scenario: Nothing to commit reported cleanly
- **WHEN** `git status` is clean
- **THEN** the skill reports "Nothing to commit" and stops

#### Scenario: HEREDOC syntax used for multi-line messages
- **WHEN** a commit message has a body
- **THEN** it is composed via HEREDOC so newlines are preserved

#### Scenario: Amend never used
- **WHEN** new commits are created
- **THEN** they are new commits, never an amend of a previous commit

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
The system SHALL push the current branch to origin with `-u`, refuse to open a PR from a protected branch (`develop`, `main`, `master`), resolve `$BASE` via the canonical chain, assemble the canonical body, and call `gh pr create --base "$BASE"` with the body. Force-push SHALL NOT be used.

#### Scenario: Protected branch blocked
- **WHEN** the current branch is `develop`, `main`, or `master`
- **THEN** the skill stops with an error directing the operator to check out a feature branch

#### Scenario: Default-branch prompt fires before any other preflight
- **WHEN** `/open-pr` runs
- **THEN** the default-branch-prompt sub-skill is invoked before checking the current branch

#### Scenario: Branch pushed with -u, not force-pushed
- **WHEN** the current branch is pushed
- **THEN** the command used is `git push -u origin HEAD` without `--force` or `--force-with-lease`

#### Scenario: Closing-keyword on non-default-branch base warned
- **WHEN** the assembled body contains a closing keyword and `$BASE` is not the GitHub default branch
- **THEN** a one-line stderr note is emitted pointing the user at `/release` (which will explicitly close the issues), but the PR is still opened

### Requirement: PR Lifecycle Orchestrator
The `/pr` skill SHALL chain `create-branch` (if on a protected branch) → `commit` (if there are uncommitted changes) → `open-pr` in sequence, stopping on the first sub-skill failure.

#### Scenario: Branch creation skipped on feature branch
- **WHEN** the current branch is not `develop`, `main`, or `master`
- **THEN** `/pr` skips `create-branch` and proceeds directly to `commit`

#### Scenario: Commit skipped on clean workspace
- **WHEN** the workspace has no changes
- **THEN** `/pr` skips `commit` and proceeds directly to `open-pr`

#### Scenario: Failure aborts the chain
- **WHEN** any sub-skill fails
- **THEN** the chain stops at that step and reports the error; no subsequent step runs

### Requirement: PR Merge
The merge-pr skill SHALL rebase-merge the open PR for the current branch (never squash, never merge-commit), delete the remote branch via `--delete-branch`, retarget any open PRs that base on this PR's head before deleting, and free the local branch when a worktree holds it — auto-checking out the base branch if the main worktree holds the head.

#### Scenario: Rebase-merge only
- **WHEN** the merge runs
- **THEN** the call uses `gh pr merge --rebase --delete-branch`; never `--squash` or `--merge`

#### Scenario: Stacked children retargeted before merge
- **WHEN** other open PRs base on this PR's head branch
- **THEN** they are retargeted before the merge runs so GitHub does not auto-close them when the head branch is deleted

#### Scenario: Main worktree holding head auto-checks out base
- **WHEN** the head branch is checked out in the main worktree (the canonical post-`push-or-pr` state)
- **THEN** the main worktree is checked out to the base branch so the head branch can be released without manual intervention

#### Scenario: Caller-owned worktree refuses removal
- **WHEN** the head branch is held by a linked worktree containing the caller's cwd
- **THEN** the script refuses with operator guidance to exit the worktree first

#### Scenario: Implicit post-merge pull wrapped against dirty workspace
- **WHEN** the workspace has uncommitted changes at merge time
- **THEN** the merge is wrapped via `with-clean-workspace` so the implicit post-merge pull does not fail with `cannot pull with rebase`

#### Scenario: Issues never closed by merge-pr
- **WHEN** `/merge-pr` lands the PR into `develop`
- **THEN** referenced issues remain open and are closed later by `/release` when work reaches `main`

### Requirement: Restack Descendants
The restack skill SHALL discover open descendant PRs of a parent PR breadth-first, rebase each onto its parent's updated head, and force-push with `--force-with-lease`. Siblings SHALL continue independently if any one branch hits a rebase conflict, with conflicted branches reported and their subtrees skipped.

#### Scenario: Auto-resolve parent from current branch
- **WHEN** `/restack` is invoked without arguments
- **THEN** the parent PR is resolved from the current branch via `gh pr list --head $BRANCH`

#### Scenario: Subtree walked breadth-first
- **WHEN** a parent has multiple direct descendants
- **THEN** all direct descendants are rebased before any of their own descendants

#### Scenario: Rebase conflict on one branch does not stop siblings
- **WHEN** one branch fails to rebase
- **THEN** sibling branches continue; the conflicted branch's own subtree is marked skipped with reason `ancestor-failed`

#### Scenario: Force-push uses lease
- **WHEN** a rebased branch is pushed
- **THEN** the command uses `git push --force-with-lease`; never plain `--force`

### Requirement: Shared-Branch Publishing
The push-or-pr skill SHALL never push directly to a shared branch (`develop`/`main` or any other checked-out branch). When pending commits exist, it SHALL save them on an auto-created dated feature branch, reset the original local branch to its upstream, push the feature branch, and open a PR against `$BASE` (default `develop`).

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

### Requirement: Develop Sync
The sync skill SHALL check out `develop`, pull the latest from origin, prune stale remote-tracking refs, and delete every local branch already merged into `develop` (excluding `develop`, `main`, and the current branch).

#### Scenario: develop checked out and pulled first
- **WHEN** sync runs
- **THEN** the first action is `git checkout develop && git pull origin develop`

#### Scenario: Stale remote refs pruned
- **WHEN** sync runs
- **THEN** `git fetch --prune` is invoked to drop stale remote-tracking refs

#### Scenario: Merged local branches deleted
- **WHEN** local branches are fully merged into `develop`
- **THEN** they are deleted, excluding `develop`, `main`, and the current branch

### Requirement: Workspace Stash Guard
The with-clean-workspace script SHALL stash tracked and untracked changes before running the wrapped command, restore the stash on success via `git stash pop`, and on stash-pop conflict leave the stash on the stack with a stderr warning while preserving the wrapped command's exit code.

#### Scenario: Missing -- separator returns usage error
- **WHEN** the script is invoked without the `--` separator
- **THEN** it exits with code 2 and prints usage text to stderr

#### Scenario: Tracked + untracked changes stashed
- **WHEN** the workspace is dirty (including untracked files)
- **THEN** they are stashed with the message `flowkit-auto-stash` before the wrapped command runs

#### Scenario: Stash restored on success
- **WHEN** the wrapped command exits zero
- **THEN** the stash is popped, restoring the workspace

#### Scenario: Stash kept on pop conflict
- **WHEN** `git stash pop` encounters a conflict after the wrapped command
- **THEN** the stash is left on the stack and a stderr warning is emitted

#### Scenario: Wrapped command exit code preserved on failure
- **WHEN** the wrapped command exits non-zero
- **THEN** the script exits with the same non-zero code and the stash remains on the stack

### Requirement: Epic Branch Creation
The cut-epic skill SHALL create a long-lived `feature/<slug>-<issue>` branch from `origin/develop`, push it to origin, and pin `claude.flowkit.prBase` to it so every subsequent PR in the repo targets the epic branch. The skill SHALL be idempotent — re-running with an existing branch reuses it and refreshes the pin.

#### Scenario: Slug inferred from issue title
- **WHEN** `$ARGUMENTS` is a single issue number
- **THEN** the slug is derived from the issue title via `gh issue view`, lower-cased, kebab-cased, and capped at 40 characters

#### Scenario: Explicit slug used verbatim
- **WHEN** `$ARGUMENTS` contains both an issue number and a kebab-case word in either order
- **THEN** they are used as `<issue>` and `<slug>` directly without re-inference

#### Scenario: Branch name capped at 60 characters
- **WHEN** the assembled branch name exceeds 60 characters
- **THEN** the slug is truncated; the issue number is preserved

#### Scenario: Reserved names rejected
- **WHEN** the resolved branch would be `main`, `master`, `develop`, or any non-`feature/`-prefixed name
- **THEN** the skill refuses to create it

#### Scenario: Branch reused if it exists
- **WHEN** the resolved branch exists locally or on origin
- **THEN** it is checked out (or fetched-and-checked-out) instead of recreated; the pin is refreshed

#### Scenario: Pin written to claude.flowkit.prBase
- **WHEN** the branch is created or reused
- **THEN** `git config claude.flowkit.prBase <branch>` is set to the epic branch name

### Requirement: Epic Promotion
The ship-epic skill SHALL rebase-merge the epic to `develop` (never squash, never merge-commit), aggregate `Closes #N` tokens from child squash commits and merged child PR bodies plus the epic issue ref, unset `claude.flowkit.prBase`, delete the epic branch, and fast-forward local `develop` when feasible.

#### Scenario: Empty pin and missing --epic stops the skill
- **WHEN** `claude.flowkit.prBase` is unset (or equals `develop`) and no `--epic` flag is passed
- **THEN** the skill stops with a "no epic in flight" message

#### Scenario: Override --epic must start with feature/
- **WHEN** `--epic <branch>` is passed
- **THEN** the branch must start with `feature/` and must not equal `develop`, `main`, or `master`

#### Scenario: Rebase-merge to develop
- **WHEN** the epic merges
- **THEN** the strategy is rebase-merge so child squash commits replay onto `develop` linearly with no merge bubble

#### Scenario: Closing tokens aggregated from squashes and child PRs
- **WHEN** building the epic PR body
- **THEN** `Closes #N` lines are aggregated from child squash commit messages, merged child PR bodies (covering the case where `gh pr merge --squash` dropped the token), and the epic issue ref; de-duplicated case-insensitively

#### Scenario: prBase unset and epic branch deleted on success
- **WHEN** the rebase-merge succeeds
- **THEN** `claude.flowkit.prBase` is cleared and the epic branch is deleted on origin

#### Scenario: Develop fast-forward skipped on different worktree
- **WHEN** the operator is on a worktree other than the main one
- **THEN** local `develop` is not touched and the result indicates `develop_advanced: false` with guidance to run `/sync`

#### Scenario: Conflict leaves state intact for retry
- **WHEN** the rebase-merge fails with a conflict
- **THEN** `claude.flowkit.prBase` and the epic branch are left intact so the operator can rebase locally and re-invoke

#### Scenario: Stacked-PR merge commits stop promotion
- **WHEN** the epic carries raw `worktree-agent-*` merge commits (meaning `swarmkit:merge-stack` was not run)
- **THEN** the skill stops with a recovery hint directing the operator to run merge-stack first

### Requirement: Release Candidate Cut
The cut skill SHALL create a release-candidate branch named `rc/YYYY-MM-DD.N` (with N as the next available counter computed from existing tags) from `origin/develop`, push it with the fully qualified refspec form, create a same-named tag, and push the tag.

#### Scenario: N derived from existing tags, not branches
- **WHEN** prior RC branches for today have been deleted but their tags remain
- **THEN** N is computed as the max existing tag suffix + 1, not the count of existing branches

#### Scenario: Always cut from origin/develop
- **WHEN** the RC branch is created
- **THEN** it is created from `origin/develop`, never from a local branch

#### Scenario: Tag pushed immediately
- **WHEN** the RC branch is pushed
- **THEN** the matching `rc/YYYY-MM-DD.N` tag is pushed immediately so future cuts see it for the N calculation

#### Scenario: Qualified refspec required by tag/branch ambiguity
- **WHEN** any subsequent push targets the RC name after the tag exists
- **THEN** the fully qualified refspec form `refs/heads/<name>:refs/heads/<name>` is used to avoid the `src refspec matches more than one` error

### Requirement: Release to Main
The release skill SHALL pick the newest `rc/*` branch from origin, rebase it onto `origin/main` and force-push, aggregate closing-keyword refs from PRs merged into `develop` since the last release tag, drop refs to already-closed issues, detect resolved epics via legacy checklist or native sub-issues, open a `release: YYYY-MM-DD` PR into `main`, rebase-merge with `--delete-branch`, sync `main`, create a `vYYYY.M.D[.N]` tag, push per-plugin tags, and explicitly close every aggregated issue idempotently.

#### Scenario: No RC branch aborts cleanly
- **WHEN** no `rc/*` branch exists on origin
- **THEN** the skill exits non-zero with guidance to run `/cut` first

#### Scenario: Unconditional rebase onto main
- **WHEN** the source RC is identified
- **THEN** it is rebased onto `origin/main` unconditionally before the PR is opened, then force-pushed with the qualified refspec form

#### Scenario: Ancestry assertion after rebase
- **WHEN** the rebase completes
- **THEN** the skill verifies `origin/main` is an ancestor of the rebased `origin/$SOURCE` and aborts if not

#### Scenario: Pre-merge divergence check before opening PR
- **WHEN** `origin/main` has commits with no patch-id equivalent on `origin/$SOURCE`
- **THEN** the skill aborts with remediation guidance (manual rebase + force-push), exiting non-zero

#### Scenario: Issue refs aggregated since last tag
- **WHEN** building the release PR body
- **THEN** `Closes/Fixes/Resolves #N` references are collected from PRs merged into `develop` since the last `v*` tag's date

#### Scenario: Already-closed issues dropped from refs
- **WHEN** an aggregated ref points at an issue already in the CLOSED state
- **THEN** that ref is dropped before the epic-detection block runs

#### Scenario: Legacy checklist epics auto-closed when children resolved
- **WHEN** an open epic's body contains `- [ ] #N` lines and every referenced child appears in this release's refs
- **THEN** `Closes #<epic>` is appended to the release PR body

#### Scenario: Native sub-issue epics auto-closed when all children resolved
- **WHEN** an open epic's children attached via the native sub-issue API are all either already closed or appear in this release's refs
- **THEN** `Closes #<epic>` is appended to the release PR body

#### Scenario: Sub-issues fetch failure surfaces non-fatally
- **WHEN** `gh api .../sub_issues` fails for an epic
- **THEN** the epic is added to a "skipped" list reported in the final summary; the release proceeds

#### Scenario: Release notes grouped by scope
- **WHEN** the release notes are built
- **THEN** bullets are grouped by conventional-commit scope, with scopes either read from `.flowkit/scopes.txt` (one per line, `#` comments ignored) or auto-detected from the commit range

#### Scenario: Auto-scope normalization
- **WHEN** scopes are auto-detected
- **THEN** sub-scopes like `flowkit:open-pr` are normalized to `flowkit` and the set is de-duplicated

#### Scenario: Rebase-merge with delete-branch
- **WHEN** the release PR merges
- **THEN** the strategy is `gh pr merge --rebase --delete-branch`; never `--squash` or `--merge`

#### Scenario: Merge wrapped against dirty workspace
- **WHEN** the workspace has uncommitted changes
- **THEN** the merge call is wrapped via `with-clean-workspace` so the implicit post-merge pull does not fail

#### Scenario: Calver tag with collision counter
- **WHEN** the tag `vYYYY.M.D` already exists on origin
- **THEN** an incrementing suffix is appended (`vYYYY.M.D.1`, `.2`, ...) until a free tag name is found

#### Scenario: Per-plugin tags pushed at release
- **WHEN** `*--v*` tags exist locally but not on origin
- **THEN** they are pushed alongside the calver tag

#### Scenario: Explicit issue close loop runs regardless of default branch
- **WHEN** every aggregated issue ref is processed
- **THEN** an idempotent `gh issue close --reason completed` loop runs against each open issue so the lifecycle completes under either `main`-default or `develop`-default repos

#### Scenario: RC branch cleanup is the safety net, not the primary cleanup
- **WHEN** `gh pr merge --delete-branch` has already removed the RC branch
- **THEN** the safety-net step finds nothing to delete and reports the no-op

### Requirement: Ship Closer
The ship skill SHALL run `cut` then `release` as a sequenced chain. Before any step runs, it SHALL abort if any open PRs with `worktree-agent-*` head branches target the resolved base. Any sub-skill failure SHALL stop the chain without proceeding.

#### Scenario: Open swarm PRs abort ship
- **WHEN** open PRs with `worktree-agent-*` head branches target the resolved base
- **THEN** ship exits non-zero with their numbers listed and a directive to run `/swarmkit:merge-stack`

#### Scenario: Resolved base equals prBase pin
- **WHEN** `claude.flowkit.prBase` is set
- **THEN** the preflight queries open PRs against the pinned base (not `develop`)

#### Scenario: jq-filtered head match
- **WHEN** the preflight checks for `worktree-agent-*` heads
- **THEN** matching is done by filtering the full open-PR JSON through `jq`'s `startswith`, not via `gh pr list --head` glob (which is exact-match only)

#### Scenario: Cut failure aborts before release
- **WHEN** `/cut` fails
- **THEN** ship stops and does not invoke `/release`

#### Scenario: No internal verify gate
- **WHEN** ship runs
- **THEN** it assumes the operator has already verified the integrated state between `/swarmkit:merge-stack` and `/ship-epic` (or between `/ship-epic` and ship); ship does not run any project-specific test/lint command of its own

### Requirement: PR-Base Scope Set/Unset
The pr-base-scope sub-skill SHALL write only to `claude.flowkit.prBase` (never to the legacy unscoped `claude.prBase`), and supports two operations: set the key to a branch name and unset the key entirely.

#### Scenario: Set writes the scoped key
- **WHEN** the Set operation runs with a branch name
- **THEN** `git config claude.flowkit.prBase <branch>` is invoked

#### Scenario: Unset clears the scoped key
- **WHEN** the Unset operation runs
- **THEN** `git config --unset claude.flowkit.prBase` is invoked

#### Scenario: Legacy key never written
- **WHEN** any set/unset operation runs
- **THEN** `claude.prBase` is never read or written

### Requirement: Pipeline Status
The pipeline-status skill SHALL be read-only, fetch the latest remote state first, and print all four pipeline stages in left-to-right order — in-flight (open PRs → develop), awaiting cut (commits on develop ahead of main), awaiting release (RC branches), and released (most recent `v*` tag) — even when stages are empty, followed by an actionable "Next step" line.

#### Scenario: Read-only behavior
- **WHEN** the skill runs
- **THEN** no branch, tag, PR, or label is mutated

#### Scenario: Fetch precedes any read
- **WHEN** the skill starts
- **THEN** `git fetch origin` runs before any read of remote state

#### Scenario: All four stages always printed
- **WHEN** any stage is empty
- **THEN** the stage is still printed with "none" rather than omitted

#### Scenario: Next step priority order
- **WHEN** multiple states could trigger a suggestion
- **THEN** the highest-priority match wins: blockers/conflicts on a PR → resolve those; approved+clean PR → merge it; non-draft unreviewed PRs → review them; RC exists → run `/release`; commits on develop but no RC → run `/cut`; otherwise → "Nothing to ship"

#### Scenario: Draft PRs never trigger a review suggestion
- **WHEN** the only unreviewed PRs are drafts
- **THEN** the "review open PRs" suggestion does not fire
