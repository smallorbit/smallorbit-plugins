# Suggest Permissions

## Purpose
Suggest Permissions scans recent session history to surface Bash commands, file edits, and MCP tools the user repeatedly approved, then proposes additions to `.claude/settings.json` so the user stops seeing the same permission prompts.

## Requirements

### Requirement: Session history location
Suggest Permissions SHALL locate session JSONL files at `~/.claude/projects/<encoded-cwd>/`, where `<encoded-cwd>` is `$PWD` with every `/` replaced by `-`. It SHALL read the five most recent files. If session history is unavailable or empty, Suggest Permissions MUST report the absence and stop.

#### Scenario: History files found
- **WHEN** JSONL files exist in the project history directory
- **THEN** the five most recent are read and scanned for approval events

#### Scenario: History unavailable
- **WHEN** no JSONL files exist in the history directory
- **THEN** Suggest Permissions reports the absence and stops

### Requirement: Pattern identification across three categories
Suggest Permissions SHALL identify repeated approvals across three categories: Bash commands (package managers, VCS, language runtimes, project scripts), file edits (source directories, file globs, config files), and MCP tools. A pattern qualifies if it appears two or more times across recent sessions, or if the user approved it without hesitation.

#### Scenario: Bash command pattern
- **WHEN** a Bash command or command class is approved two or more times
- **THEN** it appears as a Bash permission suggestion

#### Scenario: File edit pattern
- **WHEN** edits to a path or glob pattern are approved two or more times
- **THEN** it appears as an Edit permission suggestion

#### Scenario: MCP tool pattern
- **WHEN** an MCP tool is approved two or more times
- **THEN** it appears as an MCP tool permission suggestion

### Requirement: Scoped suggestions
Suggest Permissions SHALL NOT suggest wildcard patterns broader than the evidence supports. Each suggestion SHALL include a one-line rationale. Suggestions SHALL be grouped by category (Bash / Edit / MCP).

#### Scenario: Evidence-bounded suggestion
- **WHEN** only `git status` and `git log` are repeatedly approved
- **THEN** the suggestion is scoped (e.g. `Bash(git:*)` or narrower) — not `Bash(*:*)`

### Requirement: Approval gate before applying
After presenting suggestions, Suggest Permissions SHALL call `AskUserQuestion` to request approval. It MUST NOT write to any settings file before the user answers. Options SHALL include at least: apply all, select individually, and cancel.

#### Scenario: Approval requested
- **WHEN** suggestions are ready
- **THEN** `AskUserQuestion` is called before any file is written

#### Scenario: User approves
- **WHEN** the user selects "Apply all" or confirms individual items
- **THEN** Suggest Permissions merges the approved entries into `permissions.allow` and writes the settings file

#### Scenario: User cancels
- **WHEN** the user selects "Cancel"
- **THEN** no settings file is written or modified

### Requirement: Settings file target
By default, Suggest Permissions SHALL target the project-level `.claude/settings.json`. It SHALL offer `settings.local.json` as an alternative for personal preferences that should not be committed. If `.claude/settings.json` does not exist, Suggest Permissions SHALL create it with the minimal required structure.

#### Scenario: Settings file absent
- **WHEN** `.claude/settings.json` does not exist
- **THEN** Suggest Permissions creates it with the minimal structure containing the approved permissions

#### Scenario: Settings file present
- **WHEN** `.claude/settings.json` already exists
- **THEN** Suggest Permissions merges new entries into the existing `permissions.allow` array

### Requirement: Completion report
After writing, Suggest Permissions SHALL report what was added and where, and suggest running it again after a few sessions to catch new patterns.

#### Scenario: Permissions applied
- **WHEN** the settings file is written
- **THEN** Suggest Permissions reports the added entries and the file path
