# Push or PR

## Purpose

Publish pending commits on the current branch to GitHub exclusively through a pull request — never by pushing directly to the checked-out branch. When commits exist, the skill saves them onto an auto-created dated feature branch, resets the local copy of the original branch back to its upstream, pushes the feature branch, and opens a PR against the requested base. Skills that operate on a shared line such as `main` call this sub-skill so all publishing goes through review.

## Requirements

### Requirement: Shared-Branch Publishing via PR

The skill SHALL NOT push directly to the checked-out branch. When pending commits exist, it SHALL save them onto an auto-created dated feature branch, reset the local copy of the original branch to its upstream, push the feature branch, and open a pull request from that feature branch against the resolved base.

#### Scenario: Pending commits trigger feature-branch detour

- **WHEN** the current branch has commits ahead of its upstream
- **THEN** those commits are placed on an auto-created feature branch named from the supplied prefix with a `-YYYY-MM-DD` date and a numeric suffix on collision
- **AND** a PR is opened from that feature branch against the base, and `push_result` is `"pr"`

#### Scenario: Original branch reset to upstream

- **WHEN** the detour completes
- **THEN** the local copy of the original branch is reset to match `origin/<branch>` so it no longer holds the unpublished commits

#### Scenario: Checked-out branch never pushed directly

- **WHEN** commits are published
- **THEN** publishing occurs only on the auto-created feature branch and never as a direct push to the branch the operator was on

### Requirement: No-op on Clean Upstream

The skill SHALL detect when there are no pending commits and perform no publishing action in that case.

#### Scenario: No pending commits

- **WHEN** the current branch has no commits ahead of its upstream
- **THEN** the script emits `push_result` of `"noop"`, performs no push and no PR, and PR arguments are unused

### Requirement: Argument Contract

The skill SHALL accept `--prefix`, `--title`, `--body`, and `--base`. When pending commits exist, `--prefix`, `--title`, and `--body` are required; `--base` is always optional and defaults to `main`.

#### Scenario: Base defaults to main

- **WHEN** `--base` is not supplied
- **THEN** the PR is opened against `main`

#### Scenario: Explicit base honored

- **WHEN** `--base <branch>` is supplied
- **THEN** the PR is opened against that branch and `pr_url` references it

#### Scenario: Missing required PR args rejected

- **WHEN** there are pending commits and any of `--prefix`, `--title`, or `--body` is missing
- **THEN** the script exits with code 2 and writes a description of the missing argument to stderr

### Requirement: Structured Output

On success the skill SHALL emit a single bare JSON object on stdout describing the result; on failure it SHALL exit non-zero with an empty stdout and a stderr description.

#### Scenario: Success fields always present

- **WHEN** the script succeeds
- **THEN** stdout is a single JSON object containing `push_result`, `branch` (the current branch at invocation), and `pending_count` (commits ahead of upstream at invocation)

#### Scenario: PR-specific fields present on PR result

- **WHEN** `push_result` is `"pr"`
- **THEN** the JSON additionally contains `new_branch` (the feature branch carrying the saved commits) and `pr_url` (the URL of the opened PR)

#### Scenario: Failure emits nothing on stdout

- **WHEN** the script fails
- **THEN** it exits non-zero, stdout is empty, and stderr describes the failure

### Requirement: Caller-Owned Lifecycle Boundary

The skill SHALL NOT merge the opened PR, create or push tags, or run any post-merge sync; those actions remain the caller's responsibility.

#### Scenario: PR left open for caller

- **WHEN** a PR is opened
- **THEN** the skill returns its URL and does not merge it; the caller decides the merge strategy and follow-up sync

#### Scenario: Tags never pushed

- **WHEN** the script runs
- **THEN** no tag is created or pushed

### Requirement: Post-Run Working-Tree State

After a PR result, the skill SHALL leave the working tree on the auto-created feature branch, since the original branch was reset to its upstream.

#### Scenario: Working tree left on feature branch

- **WHEN** `push_result` is `"pr"`
- **THEN** the working tree is on `new_branch`, and a caller that needs the original branch must explicitly check it out and pull after the PR merges

#### Scenario: Feature branch checked out before original branch reset

- **WHEN** the original branch is reset to its upstream
- **THEN** the feature branch is already checked out first, because a branch that is currently checked out cannot be force-updated in place
