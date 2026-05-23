# Skillit

## Purpose
Skillit reflects on the current session to identify repeatable patterns worth encoding as skills. It checks the existing skill library for overlap before offering to create a new skill or extend an existing one, and writes the skill file only on explicit user approval.

## Requirements

### Requirement: Session reflection
Skillit SHALL review the conversation history and identify at least one candidate pattern — repeated instructions, step-by-step workflows, applied heuristics, fixed tool sequences, or explicit "always do this" directives from the user. Skillit MUST NOT conclude with "nothing found."

#### Scenario: Candidate identified
- **WHEN** Skillit reviews the session
- **THEN** at least one candidate pattern is surfaced

### Requirement: Existing library survey
Before proposing anything new, Skillit SHALL scan the skill library (user-global and project-local) for potential overlaps with each candidate. Skillit SHALL read the `name` and `description` front matter of any relevant candidates.

#### Scenario: Overlap found
- **WHEN** an existing skill covers the same ground as a candidate
- **THEN** Skillit surfaces the overlap before proposing the new skill, and offers to extend the existing one instead

#### Scenario: No overlap found
- **WHEN** no existing skill is close to the candidate
- **THEN** Skillit proposes creating a new skill

### Requirement: Findings presentation
Skillit SHALL describe each candidate with: what it would do (one sentence), why it's worth encoding (friction removed), and overlap risk. Skillit SHALL offer the user explicit options: create a new skill, modify an existing skill, or skip.

#### Scenario: Findings presented
- **WHEN** candidates and overlap analysis are ready
- **THEN** Skillit presents each candidate with its three-part description and the create/modify/skip options

### Requirement: Approval-gated skill creation
Skillit MUST NOT create or modify any skill file without explicit user approval. On approval, Skillit SHALL write the skill file to the user-specified path (or prompt for one). The file MUST include: YAML front matter with `name`, `description`, `triggers` (at least two), and `allowed-tools`; a `## Process` section with numbered steps; and a `## Constraints` section. Skill names SHALL be lowercase kebab-case.

#### Scenario: User approves creation
- **WHEN** the user selects "Create new skill" or "Modify existing"
- **THEN** Skillit writes (or edits) the skill file and reports the absolute path

#### Scenario: User declines
- **WHEN** the user selects "Skip"
- **THEN** Skillit makes no file changes

### Requirement: Completion confirmation
After writing the skill file, Skillit SHALL report the absolute path written. Skillit SHOULD suggest running `/skillit` again at the end of future sessions.

#### Scenario: Skill written
- **WHEN** the file is written
- **THEN** Skillit reports the absolute path
