# Commit

## Purpose
Stage and commit workspace changes following the Conventional Commits specification. The commit type, scope, and subject are derived from the staged diff rather than from an operator interview. The skill splits changes into separate logical commits when multiple unrelated concerns are present.

## Requirements

### Requirement: Inspect the workspace before staging
The skill SHALL inspect the full set of workspace changes before staging or committing anything.

#### Scenario: Read every change
- **WHEN** the skill runs
- **THEN** it SHALL read the working-tree status and both the staged and unstaged diff
- **AND** it SHALL NOT skip any changed file

#### Scenario: Accept optional freeform context
- **WHEN** the invocation supplies freeform context describing the change
- **THEN** the skill SHALL use that context to inform the subject phrasing and body
- **AND** it SHALL still derive the conventional-commit type, scope, and subject from the diff

#### Scenario: No context supplied
- **WHEN** no freeform context is supplied
- **THEN** the skill SHALL infer everything from the diff

### Requirement: Group changes by concern
The skill SHALL group the inspected changes by concern, planning one commit per unrelated concern and a single commit for a cohesive change.

#### Scenario: Single cohesive change
- **WHEN** the workspace contains one cohesive change
- **THEN** the skill SHALL create exactly one commit

#### Scenario: Multiple unrelated concerns
- **WHEN** the workspace contains changes spanning multiple unrelated concerns
- **THEN** the skill SHALL create a separate commit for each concern

#### Scenario: Atomic commits
- **WHEN** creating commits
- **THEN** each commit SHALL represent exactly one logical change
- **AND** the skill SHALL NOT mix unrelated concerns in a single commit

### Requirement: Derive conventional commit messages from the diff
Every commit message SHALL follow the Conventional Commits format, with the type, scope, and subject derived from the staged diff rather than supplied through an operator interview.

#### Scenario: Conventional format
- **WHEN** authoring a commit message
- **THEN** the message SHALL use the `type(scope): description` form
- **AND** the subject line SHALL be under 72 characters including the `type(scope): ` prefix

#### Scenario: Type inferred from change shape
- **WHEN** deriving the type
- **THEN** the skill SHALL infer it from the change shape, choosing from the allowed enum of `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, and `style`

#### Scenario: Scope inferred from changed paths
- **WHEN** deriving the scope
- **THEN** the skill SHALL infer it from the changed paths
- **AND** when the diff spans multiple plausible scopes, the skill SHALL select the dominant scope and note cross-cutting concerns in the body

#### Scenario: Body when rationale is not obvious
- **WHEN** the reason for a change is not obvious from the diff
- **THEN** the skill SHALL add a body, separated from the subject by a blank line and wrapped at 72 characters, explaining the motivation

#### Scenario: Self-explanatory subject
- **WHEN** the subject line is self-explanatory
- **THEN** the skill SHALL omit the body

### Requirement: Stage and commit per group
For each logical group, in order, the skill SHALL stage the group's files, write the derived message, and create the commit.

#### Scenario: Stage a group's files
- **WHEN** committing a group
- **THEN** the skill SHALL stage that group's files
- **AND** when grouping is complete it MAY stage all remaining changes in one pass

#### Scenario: Operator may edit before commit
- **WHEN** a message has been derived
- **THEN** the operator MAY edit the proposed message before the commit is created
- **AND** the operator SHALL NOT be prompted to supply the type, scope, or subject

### Requirement: Confirm result
After all commits are made, the skill SHALL report what was committed.

#### Scenario: Report recent log
- **WHEN** all planned commits are created
- **THEN** the skill SHALL show the recent commit log and report what was committed

### Requirement: Local-only and safe operation
The skill SHALL limit itself to creating new local commits and SHALL NOT perform branch, push, or amend operations.

#### Scenario: No branch or push
- **WHEN** committing changes
- **THEN** the skill SHALL NOT create a branch or push

#### Scenario: Never amend
- **WHEN** committing changes
- **THEN** the skill SHALL always create new commits
- **AND** it SHALL NOT amend a previous commit

#### Scenario: Nothing to commit
- **WHEN** the working tree is clean
- **THEN** the skill SHALL report "Nothing to commit" and stop
