# Merge PR

## Purpose

Squash-merge the open pull request for the current branch and delete its remote branch, keeping history linear with one commit per PR. The skill is worktree-aware so it can land PRs whose head branch lives in an agent worktree or in the main worktree.

## Input

An optional PR number. When omitted, the skill auto-detects the open PR for the current branch.

## Requirements

### Requirement: Squash-Only Merge

The skill SHALL squash-merge the open PR for the current branch and delete the remote head branch, and SHALL NOT rebase or create a merge commit.

#### Scenario: Squash and delete

- **WHEN** the user invokes the skill on a feature branch with an open PR that is ready to land
- **THEN** the skill SHALL squash-merge the PR into the base branch as a single commit
- **AND** the skill SHALL delete the remote head branch after a successful merge

#### Scenario: Linear history preserved

- **WHEN** the PR contains multiple commits
- **THEN** the skill SHALL collapse them into one commit on the base branch rather than rebasing or merge-committing

### Requirement: PR Resolution

The skill SHALL accept an explicit PR number and, when none is given, SHALL auto-detect the open PR for the current branch before attempting any merge.

#### Scenario: Explicit PR number passed

- **WHEN** the invocation includes a PR number argument
- **THEN** the skill SHALL operate on that PR

#### Scenario: PR number omitted

- **WHEN** no PR number is provided
- **THEN** the skill SHALL auto-detect the open PR for the current branch

### Requirement: Failure Surfacing

The skill MUST stop and surface the error when the merge cannot proceed, reporting the failure detail on the error channel and producing no success output.

#### Scenario: Merge fails

- **WHEN** the merge attempt fails
- **THEN** the skill SHALL surface the failure detail to the user and stop without reporting a successful merge

### Requirement: Worktree-Aware Merge

The skill SHALL clear blocking worktrees so the remote branch deletion does not fail after merge.

#### Scenario: Head branch in a non-main worktree

- **WHEN** the head branch is checked out in a worktree other than the main one
- **THEN** the skill SHALL remove that worktree before merging so the branch can be deleted

#### Scenario: Head branch in the main worktree

- **WHEN** the main worktree currently has the head branch checked out
- **THEN** the skill SHALL check out the base branch in the main worktree before merging

#### Scenario: Caller is inside the worktree holding the head

- **WHEN** the head branch is held by a worktree that contains the caller's current working directory
- **THEN** the skill MUST refuse to remove that worktree and SHALL instruct the operator to exit it first, rather than deleting its own working directory

### Requirement: Clean-Workspace Safety

The skill SHALL guard against uncommitted changes being disturbed by the implicit pull that the squash merge triggers on the local base branch.

#### Scenario: Uncommitted changes present

- **WHEN** the workspace has uncommitted changes at merge time
- **THEN** the skill SHALL auto-stash them around the merge and restore them afterward

### Requirement: Completion Reporting

The skill SHALL confirm the merged PR by number on success and SHALL still report success when only the local branch deletion fails after a successful remote merge.

#### Scenario: Successful merge

- **WHEN** the merge and remote branch deletion succeed
- **THEN** the skill SHALL confirm the merge, identifying the merged PR by its number

#### Scenario: Remote merge succeeds but local branch deletion fails

- **WHEN** the remote merge succeeds but deleting the local branch fails
- **THEN** the skill SHALL still report the merge as successful while surfacing the local-cleanup guidance
