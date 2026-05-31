# Sync

## Purpose

Return to a clean `main` state after a PR has merged: check out `main`, pull the latest from origin, prune stale remote-tracking refs, and delete local branches already merged into `main`. This is the cleanup half of the merge/sync cycle.

## Requirements

### Requirement: No Arguments

The skill SHALL take no arguments and SHALL operate against the fixed integration branch `main`.

#### Scenario: Invoked without arguments

- **WHEN** the skill runs
- **THEN** it SHALL proceed against `main` without requiring any input

### Requirement: Checkout and Pull main

The skill SHALL check out `main` and pull the latest from `origin` before any prune or cleanup step, so `main` is never left stale.

#### Scenario: main checked out and pulled first

- **WHEN** the skill runs
- **THEN** the first actions SHALL be `git checkout main` followed by `git pull origin main`

### Requirement: Prune Stale Remote-Tracking Refs

The skill SHALL prune remote-tracking refs that no longer exist on the remote.

#### Scenario: Stale remote refs pruned

- **WHEN** the skill runs
- **THEN** `git fetch --prune` SHALL be invoked to drop stale remote-tracking refs

### Requirement: Delete Merged Local Branches

The skill SHALL delete local branches that are fully merged into `main`, excluding `main` and the current branch.

#### Scenario: Merged local branches deleted

- **WHEN** local branches are fully merged into `main`
- **THEN** they SHALL be deleted, excluding `main` and the current branch

#### Scenario: main and current branch preserved

- **WHEN** evaluating branches for deletion
- **THEN** `main` and the current branch SHALL be excluded from deletion even if merged

### Requirement: Sync Summary Output

The skill SHALL print a summary covering the current HEAD (branch plus latest commit) and the local branches deleted, reporting "No merged branches to clean up" when none were deleted.

#### Scenario: Branches were deleted

- **WHEN** the cleanup step removed one or more merged branches
- **THEN** the summary SHALL list the current HEAD and the deleted branches

#### Scenario: No branches to delete

- **WHEN** no merged branches qualify for deletion
- **THEN** the summary SHALL report "No merged branches to clean up"

---

_Baselined from `plugins/flowkit/skills/sync/SKILL.md`._
