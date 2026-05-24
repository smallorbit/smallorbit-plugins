# speckit-issue

## Purpose

Quickly draft and file a single GitHub issue from a freeform description. Checks for duplicates and previews the draft before creating.

## Requirements

### Requirement: Input Handling
The skill SHALL accept a freeform issue description via `$ARGUMENTS`. When `$ARGUMENTS` is empty, the skill SHALL ask the user what the issue is about before proceeding.

#### Scenario: Description provided via arguments
- **WHEN** `$ARGUMENTS` contains a freeform description
- **THEN** the skill derives the issue title, type, priority, and body from it

#### Scenario: Empty arguments prompts for description
- **WHEN** `$ARGUMENTS` is empty
- **THEN** the skill asks the user what the issue is about before drafting anything

### Requirement: Issue Drafting
The skill SHALL derive a title (under 70 characters), type (bug/enhancement/refactor/documentation/hygiene), priority (high/medium/low, defaulting to medium), and a body with Problem, Why this matters, and Suggested fix sections.

#### Scenario: Title derived under 70 characters
- **WHEN** a description is available
- **THEN** the drafted title is specific and under 70 characters

#### Scenario: Priority inferred from description
- **WHEN** the description contains severity signals
- **THEN** the priority is inferred accordingly; when signals are absent, priority defaults to medium

### Requirement: Duplicate Check
Before presenting the draft, the skill SHALL check for existing open issues with similar titles and flag any matches.

#### Scenario: Similar existing issue flagged
- **WHEN** an open issue with a similar title exists
- **THEN** the skill flags it and asks the user whether to proceed with a new issue

#### Scenario: No similar issues proceeds without prompting
- **WHEN** no open issues with similar titles exist
- **THEN** the skill proceeds to the preview step without interruption

### Requirement: Preview Approval Gate
The skill SHALL present the draft preview and an `AskUserQuestion` approval call in the same assistant turn. Ending the turn after the preview without calling `AskUserQuestion` is a defect.

#### Scenario: Preview and approval call in same turn
- **WHEN** the draft is ready to present
- **THEN** the title, labels, and body preview are followed immediately by an `AskUserQuestion` call in the same turn

#### Scenario: Adjustment request loops back
- **WHEN** the user selects an adjust option
- **THEN** the skill updates the draft and re-presents the preview with a new `AskUserQuestion` call

### Requirement: Label Provisioning
The skill SHALL check that all labels required for the issue exist and create any that are missing before filing.

#### Scenario: Missing labels created before filing
- **WHEN** the required type or priority label does not exist in the repo
- **THEN** the skill creates the missing label to match the repo's existing label style

### Requirement: Hash Token Safety
The skill SHALL NOT write `#<number>` tokens in the issue body unless they are intentional cross-references to that exact issue. Tokens inherited from `$ARGUMENTS` SHALL be stripped or rewritten before filing.

#### Scenario: Hash tokens from arguments rewritten
- **WHEN** `$ARGUMENTS` contains a `#N` token that is not an intentional issue cross-reference
- **THEN** the skill rewrites it as "task N" or equivalent prose before including it in the body
