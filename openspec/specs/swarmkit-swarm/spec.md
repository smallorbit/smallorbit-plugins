# Swarm

## Purpose

Resolve GitHub issues in parallel by spawning isolated-worktree agents, opening stacked PRs in dependency order, running an always-on automatic review/fix pass over every PR, and leaving the PRs open for human merge. Supports one-shot mode (specific issue numbers) and loop mode (continuously clear the board), and can optionally cut an epic feature branch that all PRs target.

## Requirements

### Requirement: Argument parsing and mode selection

The skill SHALL parse its arguments to select between one-shot and loop mode and to apply per-run overrides.

#### Scenario: No arguments selects loop mode

- **WHEN** the skill is invoked with no arguments
- **THEN** it SHALL run in loop mode over all open issues targeting the base branch

#### Scenario: Label text selects filtered loop mode

- **WHEN** the argument is non-numeric label text (for example `bug` or `priority:high`)
- **THEN** it SHALL run in loop mode filtered to issues carrying that label

#### Scenario: Issue numbers select one-shot mode

- **WHEN** the argument is one or more issue numbers, bare or `#`-prefixed, or a numeric range
- **THEN** it SHALL run in one-shot mode over exactly those issues

#### Scenario: Override flags

- **WHEN** any of `--model`, `--base`, `--no-epic`, `--epic <slug>`, `--reviewer-model`, or `--worker-model` is passed
- **THEN** the skill SHALL apply that override for the run, where `--model` sets the builder model tier, `--base` overrides the default base branch, `--no-epic` suppresses epic-branch mode, `--epic` sets an explicit epic slug, and the reviewer/worker model flags override the review pass and fix-round models respectively

### Requirement: Epic mode resolution

The skill SHALL compute whether to run in epic mode before any setup work, and when epic mode is on it MUST cut or resume a single epic feature branch that all PRs target.

#### Scenario: Epic mode is disabled

- **WHEN** `--base` is set, OR `--no-epic` is set, OR the run is one-shot with exactly one issue
- **THEN** epic mode SHALL be off, no epic branch is cut, and PRs target the base branch directly

#### Scenario: Epic mode is enabled

- **WHEN** none of the disabling conditions hold
- **THEN** epic mode SHALL be on and the skill SHALL resolve an epic branch name of the form `feature/<slug>-<N>` or `feature/<slug>-<date>` and cut it from the default branch

#### Scenario: Resuming an existing epic branch

- **WHEN** the resolved epic branch already exists on the remote
- **THEN** the skill SHALL fetch and check it out instead of recreating it, and refresh the pinned base configuration

#### Scenario: Conflicting pinned epic guard

- **WHEN** the preflight is invoked to scope the pinned base and a pinned base is already set to a different epic branch (one starting with `feature/`) than the one about to be pinned
- **THEN** the preflight SHALL refuse to run, exit non-zero, and instruct the operator to pass `--no-epic` or reuse the pinned slug — the guard is enforced in the preflight script so any direct caller is protected

#### Scenario: Empty board at loop entry

- **WHEN** epic mode is on in loop mode and the board is clear at entry
- **THEN** the skill SHALL defer cutting the epic branch until a cycle selects at least one issue, and if the board stays clear it announces the board is clear and exits without cutting a branch

### Requirement: Preflight verification

The skill SHALL run a preflight step that fetches, verifies the base branch exists (creating it from the default branch when missing), and confirms authentication before any agents are spawned.

#### Scenario: Authentication missing

- **WHEN** the preflight reports authentication is not present
- **THEN** the skill SHALL stop immediately and surface the error — no swarm work proceeds

#### Scenario: Base branch created

- **WHEN** the preflight reports it created the base branch from the default branch
- **THEN** the skill SHALL announce that the base branch was created and that all PRs will target it

#### Scenario: Preflight failure

- **WHEN** the preflight exits non-zero
- **THEN** the skill SHALL surface the human-readable error and stop

### Requirement: Verify-command resolution

The skill SHALL resolve the project's verify command once at the start of the run and reuse it for every fix-round worker.

#### Scenario: Explicit repo override

- **WHEN** a repo-level verify command is configured
- **THEN** the skill SHALL use that command

#### Scenario: Project convention fallback

- **WHEN** no explicit override exists but the project declares a verify script
- **THEN** the skill SHALL select the command using the project's package manager

#### Scenario: No verify command resolvable

- **WHEN** neither an override nor a project convention resolves and no default toolchain is detected
- **THEN** the skill SHALL warn and instruct workers to skip the verify step rather than run a command that will fail

### Requirement: Issue gathering and skip rules

The skill SHALL gather full issue details in one batch and SHALL skip ineligible issues, expanding epics into their wired child issues.

#### Scenario: Skipping ineligible issues

- **WHEN** a requested issue is closed or carries an on-hold label
- **THEN** the skill SHALL skip it and announce the skip

#### Scenario: Expanding an epic

- **WHEN** a requested issue is an epic with children wired via the native sub-issue API
- **THEN** the skill SHALL swarm the eligible children and announce which were swarmed and which were skipped

#### Scenario: Unwired epic

- **WHEN** a requested issue is labeled as an epic but has no children wired via the native sub-issue API
- **THEN** the skill SHALL skip it, announce that children must be attached first, and proceed with the remaining work items

#### Scenario: Every requested issue skipped

- **WHEN** all requested issues are skipped
- **THEN** the skill SHALL announce and stop

### Requirement: Dependency analysis and stacked planning

The skill SHALL build a dependency graph from each issue's native dependency edges, falling back to body references, and produce a topological ordering that drives parallel spawning and stacked PR targeting.

#### Scenario: Independent issues

- **WHEN** an issue has no dependencies within the batch
- **THEN** it SHALL be eligible to spawn in parallel targeting the base branch

#### Scenario: Dependent issues

- **WHEN** an issue depends on another in the batch
- **THEN** it SHALL wait for its dependency's PR to be created and branch from the dependency's branch tip, with its PR targeting the dependency's branch

#### Scenario: File-conflict grouping

- **WHEN** multiple issues touch the same files
- **THEN** they MUST NOT be split across agents that would collide, and small independent same-file fixes MAY be grouped into one agent

#### Scenario: Plan presentation

- **WHEN** the plan is computed
- **THEN** the skill SHALL present a table of agents, issues, branches, affected files, and models, and proceed with the proposed groupings

### Requirement: Agent spawning contract

The skill SHALL spawn each builder agent in an isolated worktree on a `worktree-agent-<issue>` branch, and each builder MUST run to a reported PR URL as its only acceptable termination.

#### Scenario: Isolation and naming

- **WHEN** a builder agent is spawned
- **THEN** it SHALL run with worktree isolation, bypass-permission mode, in the background, on a branch named `worktree-agent-<issue>`

#### Scenario: Worktree safety checks

- **WHEN** a builder begins its workflow
- **THEN** it SHALL check out its branch from `origin/<base>`, abort if it is not running inside an isolated worktree, and abort if its HEAD does not descend from `origin/<base>`

#### Scenario: In-progress labeling

- **WHEN** an issue is about to be worked
- **THEN** the skill SHALL ensure an in-progress status label exists and apply it to the issue

#### Scenario: Builder termination

- **WHEN** a builder finishes its work
- **THEN** it SHALL commit using conventional-commit format with no attribution lines, push its branch, open a PR with a Summary and Test plan body that closes the issue, and report the PR URL as its only acceptable termination condition

#### Scenario: Builders are not re-addressable

- **WHEN** a builder has reported its PR
- **THEN** the orchestrator SHALL treat the builder as no longer addressable and SHALL NOT attempt to message it

### Requirement: Completion handling

The skill SHALL verify each agent's output after it completes and recover gracefully when a builder under-produces.

#### Scenario: No branch and no push

- **WHEN** an agent produced neither a pushed branch nor a local branch
- **THEN** the skill SHALL announce the unrecoverable failure and treat the issue as failed without attempting PR creation

#### Scenario: Branch present but PR missing

- **WHEN** an agent pushed a branch but opened no PR
- **THEN** the skill SHALL create the PR on the agent's behalf using the agent's commits and the issue spec

#### Scenario: PR already present

- **WHEN** an agent already opened its PR
- **THEN** the skill SHALL record the PR link and take no further creation action

### Requirement: Automatic review and fix pass

Every confirmed PR SHALL pass through an always-on review/fix pass with no flag to disable it, spawning a read-only reviewer per PR and a fresh fix-round worker only when the reviewer verdict is non-clean.

#### Scenario: Reviewer per PR

- **WHEN** a PR is confirmed
- **THEN** the skill SHALL spawn a read-only reviewer agent that returns a structured verdict with blockers, concerns, nits, and tagged coverage gaps inline to the orchestrator

#### Scenario: Clean verdict skips the fix round

- **WHEN** the reviewer returns an approve verdict with no blockers, no concerns, and no recommended coverage gaps
- **THEN** the skill SHALL NOT spawn a fix-round worker and the PR stands as-is

#### Scenario: Non-clean verdict spawns a fresh worker

- **WHEN** the reviewer reports any blocker, any concern, or any recommended coverage gap
- **THEN** the skill SHALL spawn a fresh worker branched from the existing PR head — never the original builder — to apply in-scope findings, run the verify command, commit, and push to the same branch

#### Scenario: Reviewer returns no output

- **WHEN** a reviewer crashes or delivers no verdict payload
- **THEN** the skill SHALL leave the PR open without a fix pass and note the missing review in the final summary

#### Scenario: Fix-round push rejected

- **WHEN** a fix-round worker's push is rejected because the branch advanced underneath it
- **THEN** the worker SHALL re-fetch and rebase, and abort and report if conflicts arise, and MUST NOT push a red build

### Requirement: Loop mode iteration

In loop mode the skill SHALL repeatedly select a safely-parallelizable batch and swarm it until the board is clear or the operator stops, halting only on unrecoverable failures.

#### Scenario: Batch selection per cycle

- **WHEN** a loop cycle begins
- **THEN** the skill SHALL fetch and rank open issues, apply any label filter, and select issues that do not share files and have no unresolved intra-batch dependencies

#### Scenario: Board clear

- **WHEN** no open issues remain
- **THEN** the skill SHALL announce the board is clear and exit

#### Scenario: Cycle checkpoint

- **WHEN** a cycle completes
- **THEN** the skill SHALL print a checkpoint summarizing opened PRs, failures, blocked issues, and remaining issues, then proceed to the next cycle

#### Scenario: Unrecoverable failure halts the loop

- **WHEN** an agent crashes producing no PR, or the base branch is deleted or corrupted externally
- **THEN** the skill SHALL halt the loop and route through teardown before terminating so the pinned base is cleared, never exiting in place

### Requirement: Cleanup and teardown

The skill SHALL clean up agent worktrees and orphaned branches after a run and restore the base branch and pinned configuration.

#### Scenario: Worktree cleanup

- **WHEN** a run completes
- **THEN** the skill SHALL remove agent worktrees and orphaned local `worktree-agent-*` branches

#### Scenario: Pinned-base teardown

- **WHEN** teardown runs and epic mode was off
- **THEN** the skill SHALL restore the base branch and unset the pinned base configuration

#### Scenario: Teardown runs on every exit path

- **WHEN** a run ends in one-shot mode, or a loop ends by board-clear, user stop, or unrecoverable failure
- **THEN** the skill SHALL run teardown before terminating so the pinned base configuration is always cleared (or preserved via the epic-keep flag in epic mode) — no exit path bypasses teardown

#### Scenario: Epic branch preserved

- **WHEN** teardown runs and epic mode was on
- **THEN** the skill SHALL leave the epic branch in place with the pinned base configuration and instruct the operator to land child PRs, open a final epic-to-main PR, then unset the pin and delete the epic branch

### Requirement: Final reporting and next step

The skill SHALL report the outcome of the run and point the operator to the correct merge path.

#### Scenario: Run summary

- **WHEN** a run completes
- **THEN** the skill SHALL emit a table of issues, PRs, branches, and open status, leaving all PRs open for review

#### Scenario: Merge-path guidance

- **WHEN** the summary is presented
- **THEN** the skill SHALL direct the operator to merge a single open PR with the single-PR merge skill, or to merge two or more stacked PRs bottom-up with the merge-stack skill
