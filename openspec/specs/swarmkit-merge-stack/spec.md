# Merge Stack

## Purpose

Merge a stack of open swarm pull requests (`worktree-agent-*` head branches) into the base branch in one pass. Retarget every non-root PR onto the base branch, then squash-merge bottom-up so the integrated work lands on the base as a clean linear sequence of squashed commits.

## Requirements

### Requirement: Inputs and Defaults

The skill SHALL accept an optional base-branch override and an optional dry-run flag, defaulting to the repository's default branch and to mutating execution respectively.

#### Scenario: Default base branch

- **WHEN** the user runs merge-stack without a base override
- **THEN** the skill SHALL target the repository's default branch as the base to retarget and merge into

#### Scenario: Explicit base override

- **WHEN** the user supplies a base-branch argument
- **THEN** the skill SHALL retarget and merge the stack into that branch instead of the default

#### Scenario: Dry-run preview

- **WHEN** the user requests a dry run
- **THEN** the skill SHALL print the merge plan
- **AND** SHALL NOT retarget, merge, delete, or otherwise mutate any branch or PR

### Requirement: Preconditions

The skill SHALL require an authenticated GitHub CLI session and a clean working tree before attempting any mutation.

#### Scenario: Clean working tree required

- **WHEN** merge-stack begins
- **THEN** it SHALL expect a clean working tree so that the local base checkout does not clobber uncommitted changes

### Requirement: Stack Discovery

The skill SHALL enumerate open pull requests whose head branch matches the `worktree-agent-*` prefix and SHALL exit successfully without changes when none exist.

#### Scenario: Swarm PRs present

- **WHEN** there are open PRs with `worktree-agent-*` head branches
- **THEN** the skill SHALL collect those PRs as the stack to integrate

#### Scenario: No swarm PRs

- **WHEN** there are no open `worktree-agent-*` PRs
- **THEN** the skill SHALL report that there are no open swarm PRs to merge
- **AND** SHALL exit successfully without mutating anything

### Requirement: Merge Ordering

The skill SHALL merge the discovered PRs bottom-up in ascending PR-number order, treating the lowest-numbered PR as the root of the stack.

#### Scenario: Ascending number order

- **WHEN** the stack contains multiple PRs
- **THEN** the skill SHALL sort them by ascending PR number and merge the lowest first

### Requirement: Retarget Non-Root PRs

The skill SHALL retarget every PR whose base is not already the target base branch onto the base branch before merging, collapsing the stack so each PR merges directly into the base.

#### Scenario: Retarget a stacked PR

- **WHEN** a PR's base branch is not the target base branch
- **THEN** the skill SHALL change that PR's base to the target base branch

#### Scenario: Root PR already targets base

- **WHEN** a PR already targets the base branch
- **THEN** the skill SHALL leave its base ref unchanged

### Requirement: Squash Merge and Branch Deletion

The skill SHALL merge each PR using a uniform squash strategy and SHALL delete the remote head branch on merge. The skill MUST NOT use rebase or merge-commit strategies and MUST NOT force-push.

#### Scenario: Squash and delete

- **WHEN** the skill merges a PR in the stack
- **THEN** it SHALL squash-merge the PR
- **AND** SHALL delete the remote `worktree-agent-*` head branch after the merge

#### Scenario: Strategy is squash-only

- **WHEN** integrating any PR in the stack
- **THEN** the skill SHALL NOT use a rebase or merge-commit strategy
- **AND** SHALL NOT edit PR contents beyond the base ref

### Requirement: Stop on Merge Failure

The skill SHALL halt the run on the first failed merge and report the blocking PR, leaving the remaining PRs unmerged.

#### Scenario: Merge blocked by conflict or check

- **WHEN** a PR fails to merge due to a conflict or a failing required check
- **THEN** the skill SHALL stop and report which PR blocked the stack
- **AND** SHALL NOT continue merging the remaining PRs

### Requirement: Sync Local Base

After all merges succeed, the skill SHALL update the local base branch to reflect the integrated history.

#### Scenario: Sync after success

- **WHEN** every PR in the stack has merged successfully
- **THEN** the skill SHALL check out the base branch and pull the latest integrated history

### Requirement: Run Report

The skill SHALL report the outcome of the run, including how many PRs were merged, any blocking PR with its reason, and the final state of the base branch.

#### Scenario: Reporting results

- **WHEN** the run completes or halts
- **THEN** the skill SHALL report the number of PRs merged, any blocking PR with its reason, and whether the base branch was synced
