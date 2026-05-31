# Fetch Issues

## Purpose

The gh-fetch-issues skill is the canonical fetch-and-filter pattern for open GitHub issues. It retrieves open issues and excludes issues that are parked behind an on-hold label or already claimed by an in-progress agent, so consumer skills receive only issues that are ready to be worked. It is an internal sub-skill used by next-issue, swarm, and catalog rather than a user-facing command.

## Requirements

### Requirement: Fetch Open Issues

The skill SHALL fetch open GitHub issues and return them as a structured collection that consumer skills can rank, sort, recommend from, or select against.

#### Scenario: Fetching open issues

- **WHEN** a consumer skill requests the list of open issues
- **THEN** the skill SHALL retrieve issues whose state is open
- **AND** SHALL return them in a structured (JSON) form

#### Scenario: Structured issue fields

- **WHEN** issues are returned
- **THEN** each issue SHALL carry at least its number, title, body, and labels so downstream skills can rank and present it

### Requirement: Fetch Ceiling

The skill SHALL retrieve open issues up to a bounded ceiling in a single pass.

#### Scenario: Bounded single-pass fetch

- **WHEN** the fetch runs
- **THEN** it SHALL request up to 50 open issues in a single pass rather than fetching an unbounded number

### Requirement: On-Hold Exclusion

The skill SHALL exclude every issue carrying an on-hold label, and such issues MUST NOT be surfaced, ranked, or recommended because they are not ready to be worked.

#### Scenario: Issue carrying an on-hold label

- **WHEN** an open issue carries the on-hold label
- **THEN** the skill SHALL omit that issue from the returned collection
- **AND** SHALL NOT surface, rank, or recommend it

#### Scenario: Issue without an on-hold label

- **WHEN** an open issue does not carry the on-hold label
- **THEN** the skill SHALL retain that issue in the returned collection unless another exclusion rule applies

### Requirement: In-Progress Exclusion

The skill SHALL exclude every issue carrying a status:in-progress label, because such issues are actively being worked on by a swarm agent and MUST NOT be re-picked until that agent completes.

#### Scenario: Issue actively claimed by an agent

- **WHEN** an open issue carries the status:in-progress label
- **THEN** the skill SHALL omit that issue from the returned collection so it is not re-picked

#### Scenario: Issue released by its agent

- **WHEN** an issue no longer carries the status:in-progress label
- **THEN** the skill SHALL again make that issue eligible to be returned, subject to the on-hold exclusion

### Requirement: Selection Delegated to the Caller

The skill SHALL own only the open-state fetch and the on-hold and in-progress exclusions; all other selection concerns SHALL belong to the calling skill.

#### Scenario: Caller owns ranking and recommendation

- **WHEN** the filtered collection is returned to a consumer skill
- **THEN** ranking, prioritization, and recommendation SHALL be performed by the calling skill, not by the fetch skill
