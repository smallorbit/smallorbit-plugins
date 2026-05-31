# Jot

## Purpose
Jot is a quick-capture entry point for the active Obsidian project. It records a decision, task, note, or progress update mid-conversation by delegating to the `vaultkit:project` skill's Update Project Files operation, so the user can persist a thought without invoking the full project workflow directly.

## Requirements

### Requirement: Invocation Triggers
The skill SHALL activate when the user expresses an intent to quickly capture or update project notes. It SHOULD recognize phrasing such as "jot this down", "update my notes", "record this decision", "save progress", or "update the project notes".

#### Scenario: Quick-capture phrasing
- **WHEN** the user says "jot this down", "update my notes", "record this decision", "save progress", or "update the project notes"
- **THEN** the skill activates to capture the content into the active project

### Requirement: Argument Handling
When invocation arguments are provided, the skill SHALL treat that argument text as the specific note, decision, or task to record.

#### Scenario: Arguments supplied
- **WHEN** the skill is invoked with argument text
- **THEN** the skill treats that text as the specific note, decision, or task to record

#### Scenario: No arguments supplied
- **WHEN** the skill is invoked without argument text
- **THEN** the skill still proceeds via the delegated operation, which determines what to capture from conversation context

### Requirement: Delegation to Project Update
The skill SHALL delegate to the `vaultkit:project` skill's Update Project Files operation (Operation 3) rather than implementing the capture logic itself.

#### Scenario: Hand off to project update
- **WHEN** content is to be captured
- **THEN** the skill invokes the `vaultkit:project` skill's Update Project Files operation
- **AND** the skill does not perform the update logic directly

### Requirement: Active Project Resolution
The skill SHALL rely on the delegated operation to identify the active project, either from conversation context or by prompting the user.

#### Scenario: Active project resolved from context
- **WHEN** an active project can be inferred from conversation context
- **THEN** the delegated operation targets that project

#### Scenario: Active project not in context
- **WHEN** no active project can be inferred from conversation context
- **THEN** the delegated operation prompts the user to identify the project

### Requirement: Birth-Time-Preserving Edits
The skill SHALL ensure edits to existing project files are written in place via the `vaultkit:file-edit` path so the file's filesystem birth time is preserved, and SHALL ensure the relevant file is read before being edited.

#### Scenario: Editing an existing project file
- **WHEN** the delegated operation modifies an existing project file
- **THEN** the relevant file is read before editing
- **AND** the edit is written in place to preserve the file's birth time

### Requirement: Change Classification
The skill SHALL, through the delegated operation, determine what kind of change is being recorded — a decision, a task, a status update, or a blocker — and capture it accordingly.

#### Scenario: Classifying the captured change
- **WHEN** content is captured
- **THEN** the delegated operation classifies it as a decision, task, status update, or blocker

### Requirement: Concise Recall Entries
The skill SHALL keep captured entries concise — recall notes rather than full documentation.

#### Scenario: Recording an entry
- **WHEN** an entry is written to a project file
- **THEN** the entry is kept concise as a recall note rather than expanded into documentation
