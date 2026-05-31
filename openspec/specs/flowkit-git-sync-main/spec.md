# Git Sync Main

## Purpose

Bring the local repository onto the trunk branch and update it to match the remote. This is a small, composable sub-skill used by the release flow to guarantee that downstream steps (tagging, shipping) run against the latest integrated state of the trunk.

## Requirements

### Requirement: Check out the trunk branch

The skill SHALL switch the working repository to the trunk branch (`main`) before pulling, so subsequent steps operate against the canonical integration branch.

#### Scenario: Repository is on a non-trunk branch

- **WHEN** the skill runs while the repository is checked out on a branch other than the trunk
- **THEN** it SHALL check out the trunk branch before performing any pull

#### Scenario: Repository is already on the trunk branch

- **WHEN** the skill runs while the trunk branch is already checked out
- **THEN** it SHALL proceed to update the trunk branch without an unnecessary branch switch

### Requirement: Pull the latest from origin

The skill SHALL update the local trunk branch with the latest commits from the remote origin so that the local trunk matches the published trunk.

#### Scenario: Remote has new commits

- **WHEN** origin's trunk branch contains commits not present locally
- **THEN** the skill SHALL fast-forward the local trunk branch to incorporate those commits

#### Scenario: Local trunk is already current

- **WHEN** the local trunk branch already matches origin's trunk branch
- **THEN** the skill SHALL complete successfully with the trunk left up to date

### Requirement: Serve as a release sub-skill

The skill SHALL behave as a composable sub-skill that the release flow invokes to establish an up-to-date trunk before tagging and shipping.

#### Scenario: Invoked by the release flow

- **WHEN** the release flow needs to operate against the latest trunk state
- **THEN** it MAY call this skill to check out and update the trunk, after which the release flow continues with the trunk synchronized to origin
