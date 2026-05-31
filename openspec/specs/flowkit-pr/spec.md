# Wrap Up and Open PR

## Purpose

Wrap up the current branch end to end in a single step: commit any pending workspace changes, then push the branch and open a pull request against the base branch. It is a thin convenience wrapper that chains the commit flow and the open-PR flow without introducing new behavior.

## Requirements

### Requirement: Legacy Workflow Refusal

The skill SHALL refuse to run in a repository still configured for the legacy develop/main split, directing the operator to migrate to single-trunk first.

#### Scenario: Legacy develop-default repository

- **WHEN** the repository's default branch is `develop`, or `develop` exists on origin while `main` does not
- **THEN** the skill stops with a non-zero exit and directs the operator to run the v4 migration before using the skill

#### Scenario: Single-trunk repository

- **WHEN** the repository is already on the single-trunk layout
- **THEN** the skill proceeds past the preflight check

### Requirement: Protected Branch Guard

The skill MUST NOT open a pull request from a protected branch and SHALL require the operator to have created a feature branch first, since branch creation is the operator's responsibility.

#### Scenario: On a protected branch

- **WHEN** the current branch is `main` or `master`
- **THEN** the skill stops and reports that the operator must check out a feature branch before opening a pull request

#### Scenario: On a feature branch

- **WHEN** the current branch is any non-protected branch
- **THEN** the skill proceeds to commit and open the pull request

### Requirement: Fail-Fast Chaining

The skill SHALL run its steps in sequence and SHALL stop on the first step that fails, reporting the error rather than continuing.

#### Scenario: A step fails

- **WHEN** the commit step or the open-PR step fails
- **THEN** the skill stops at that step, reports the error, and does not run any subsequent step

### Requirement: Commit Pending Changes

The skill SHALL commit any uncommitted workspace changes by running the commit flow before opening a pull request, and SHALL skip committing when the workspace is already clean.

#### Scenario: Uncommitted changes present

- **WHEN** the workspace has staged or unstaged changes
- **THEN** the skill runs the commit flow to stage and create one or more conventional commits
- **AND** unrelated changes are split into separate commits

#### Scenario: Clean workspace

- **WHEN** the workspace has no uncommitted changes
- **THEN** the skill skips committing and proceeds straight to opening the pull request

### Requirement: Open Pull Request

The skill SHALL push the current branch and open a pull request against the base branch by running the open-PR flow.

#### Scenario: Push and open PR

- **WHEN** the branch has commits ready to publish
- **THEN** the skill pushes the current branch and opens a pull request against `main` or the pinned base branch

#### Scenario: Existing PR

- **WHEN** there is nothing to commit and the branch is already pushed with an open pull request
- **THEN** the skill reports the existing pull request instead of opening a duplicate

### Requirement: Base Branch Resolution

The skill SHALL resolve the pull request base branch the same way the open-PR flow does, honoring a pinned base branch when one is configured and otherwise targeting `main`.

#### Scenario: Pinned base configured

- **WHEN** a pinned base branch is configured for the repository
- **THEN** the skill opens the pull request against the pinned base

#### Scenario: No pinned base

- **WHEN** no pinned base branch is configured
- **THEN** the skill opens the pull request against `main`

### Requirement: Report Outcome

The skill SHALL report the pull request URL together with a one-line summary of what was committed, if anything, and what was opened.

#### Scenario: Report after wrap-up

- **WHEN** the skill finishes committing and opening or locating the pull request
- **THEN** it surfaces the pull request URL and a one-line summary of the committed work and the opened pull request
