# speckit-catalog

## Purpose

Convert code review findings or assessment results into prioritized, labeled GitHub issues. Accepts findings from explicit input, conversation context, or a file path.

## Requirements

### Requirement: Finding Extraction
The skill SHALL parse the source input into discrete findings, each with a title (under 70 characters), category (bug/enhancement/refactor/documentation/hygiene), severity (high/medium/low), and body.

#### Scenario: Explicit input parsed into findings
- **WHEN** `$ARGUMENTS` contains a pasted list or structured findings text
- **THEN** the skill extracts one finding object per discrete finding with title, category, severity, and body

#### Scenario: Conversation context used when arguments empty
- **WHEN** `$ARGUMENTS` is empty and earlier conversation contains structured findings from a code review or assessment
- **THEN** the skill uses those findings as the source

#### Scenario: File path resolved to findings
- **WHEN** `$ARGUMENTS` is a file path
- **THEN** the skill reads the file and extracts findings from its contents

#### Scenario: No findings available
- **WHEN** no findings can be derived from arguments, context, or file
- **THEN** the skill asks the user what to catalog before proceeding

### Requirement: Phase Consolidation
By default, the skill SHALL consolidate mechanically-related findings in the same phase into a single issue. A finding qualifies for consolidation only when it shares scope with phase-mates AND has no inter-dependencies with them. The `--split` flag disables consolidation and files one issue per finding.

#### Scenario: Same-phase same-scope findings consolidated
- **WHEN** multiple findings share a phase label and describe instances of the same mechanical work with no inter-dependencies
- **THEN** they are merged into a single issue whose body lists each original finding as a checklist item

#### Scenario: Split flag bypasses consolidation
- **WHEN** `--split` is present in `$ARGUMENTS`
- **THEN** every finding becomes its own issue regardless of phase or scope

#### Scenario: Findings with inter-dependencies stay separate
- **WHEN** one finding in a phase lists another finding in the same phase as a prerequisite or dependency
- **THEN** those two findings are not consolidated

### Requirement: Consolidation Summary
The skill SHALL print a one-line-per-phase consolidation summary before the catalog table, even when `--auto` is active or no consolidation occurred.

#### Scenario: Summary printed before catalog table
- **WHEN** the catalog table is about to be presented
- **THEN** a consolidation summary line per phase is emitted first, showing rows → issues and the consolidation reason

#### Scenario: Split mode summary
- **WHEN** `--split` is active
- **THEN** the summary is a single line stating that one issue per row will be filed

### Requirement: Label Provisioning
The skill SHALL ensure all labels required for the current batch exist in the repo before filing. Labels are created only when they will be used by the current findings.

#### Scenario: Missing category or priority labels created
- **WHEN** a finding requires a category or priority label that does not exist in the repo
- **THEN** the skill creates the missing label before filing

#### Scenario: Epic label created when slug supplied and missing
- **WHEN** `--epic <slug>` is present and the `epic:<slug>` label does not exist
- **THEN** the skill creates the label with color `#5319E7` and a description referencing the epic title or slug

#### Scenario: Existing epic label requires confirmation before reuse
- **WHEN** `--epic <slug>` is present and the `epic:<slug>` label already exists
- **THEN** the skill warns the user and asks for explicit approval before reusing the label for the batch

### Requirement: Catalog Approval Gate
The skill SHALL present the catalog table and an `AskUserQuestion` approval call in the same assistant turn before creating any issues. The `--auto` flag skips the approval gate.

#### Scenario: Catalog table and approval call in same turn
- **WHEN** the catalog is ready to present and `--auto` is not active
- **THEN** the catalog table and an `AskUserQuestion` call appear in the same assistant turn with no turn-ending prose between them

#### Scenario: Auto flag bypasses approval
- **WHEN** `--auto` is present in `$ARGUMENTS`
- **THEN** the skill proceeds directly to issue creation without presenting the catalog for approval

#### Scenario: Epic label column shown in catalog table
- **WHEN** `--epic <slug>` is active
- **THEN** every row in the catalog table shows the `epic:<slug>` label in the Labels column

### Requirement: Sequential Issue Creation
The skill SHALL create issues one at a time in priority order (high first). Parallel creation is forbidden.

#### Scenario: Issues created sequentially in priority order
- **WHEN** the user approves the catalog
- **THEN** issues are created one at a time from highest to lowest priority, and each URL is captured immediately after creation

#### Scenario: Epic label applied to every issue in batch
- **WHEN** `--epic <slug>` is active
- **THEN** every `gh issue create` call includes `--label "epic:<slug>"` alongside category and priority labels

### Requirement: Title–Number Verification
After creating all issues, the skill SHALL verify that each created issue's title matches the intended title before reporting or passing numbers downstream.

#### Scenario: Created issue titles verified
- **WHEN** all issues in the batch have been created
- **THEN** the skill fetches each issue's title via `gh issue view` and asserts it matches the catalog table row

#### Scenario: Mismatch halts reporting
- **WHEN** any retrieved title does not match the intended title
- **THEN** the skill halts and reports the mismatch without passing unverified issue numbers downstream

### Requirement: Handoff Block Emission
When invoked with `--epic <slug>`, the skill SHALL emit a fenced `spec-handoff` JSON block as the final output after the issue table, with no trailing prose.

#### Scenario: Handoff block emitted after epic-mode issue table
- **WHEN** `--epic <slug>` is present and all issues have been created and verified
- **THEN** a fenced block with info string `spec-handoff` containing `filed`, `epic_slug`, and `next_phase` fields is the last element of the output

#### Scenario: Handoff block omitted without epic flag
- **WHEN** `--epic <slug>` is not present
- **THEN** no `spec-handoff` block appears in the output
