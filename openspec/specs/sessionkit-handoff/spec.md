# Handoff

## Purpose
Handoff captures the current session's goal, progress, remaining work, context, and task list into `.sessionkit/HANDOFF.md` so another agent can resume the work without losing momentum. The entire skill runs inline — no sub-agent dispatch, no fingerprinting, no delta/full routing.

## Requirements

### Requirement: Inline synthesis
Handoff SHALL synthesize the document in the active session without dispatching a sub-agent. The session SHALL gather the task list via `TaskList`/`TaskGet`, derive all document sections from the live conversation, and write the document directly to disk.

#### Scenario: Always inline
- **WHEN** Handoff is invoked from any session
- **THEN** the document is synthesized and written inline, with no sub-agent dispatched

### Requirement: Context collection
Handoff SHALL collect the task list before synthesizing the document. The session MUST call `TaskList`, then `TaskGet` once per task ID, before writing any section. All sections are derived from the live conversation and the collected task list.

#### Scenario: Task list collected
- **WHEN** Handoff is invoked
- **THEN** `TaskList` and `TaskGet` are called to collect non-deleted tasks before synthesis begins

### Requirement: Document structure
The handoff document SHALL follow a fixed section order: Goal → Progress → Remaining Work → Context → Task List. All content in Progress, Remaining Work, and Context SHALL be bullets only — no narrative paragraphs. The document SHALL start with `# Handoff` followed immediately by the first section heading — no metadata lines between the title and `## Goal`.

#### Scenario: Section order
- **WHEN** a handoff document is written
- **THEN** sections appear in canonical order: Goal → Progress → Remaining Work → Context → Task List

#### Scenario: Bullet-only sections
- **WHEN** Progress, Remaining Work, or Context content is generated
- **THEN** every entry is a bullet — no narrative paragraphs

### Requirement: Task list serialization
The `## Task List` section SHALL contain exactly one fenced `json` code block. Each task object SHALL include only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, and `blocks`. Deleted tasks SHALL be excluded. The original task `id` SHALL be preserved so `/pickup` can rewire `blockedBy` relationships. The block SHALL emit `[]` when there are no tasks.

#### Scenario: Task list in JSON block
- **WHEN** the document is written
- **THEN** `## Task List` contains a fenced `json` block with one object per non-deleted task, using the original task IDs

#### Scenario: No tasks
- **WHEN** the session has no non-deleted tasks
- **THEN** `## Task List` contains a fenced `json` block containing `[]`

### Requirement: Gitignore coverage
Before writing, Handoff SHALL check whether `.sessionkit/` is covered by `.gitignore`. If `.gitignore` is absent or does not cover `.sessionkit/`, Handoff SHALL ask the user before adding coverage. Handoff MUST NOT modify `.gitignore` without user confirmation.

#### Scenario: Gitignore absent
- **WHEN** no `.gitignore` file exists
- **THEN** Handoff asks the user whether to create one with `.sessionkit/`

#### Scenario: Gitignore present but uncovered
- **WHEN** `.gitignore` exists but does not cover `.sessionkit/`
- **THEN** Handoff asks the user whether to append `.sessionkit/`

#### Scenario: Already covered
- **WHEN** `.gitignore` already covers `.sessionkit/`
- **THEN** Handoff proceeds silently

### Requirement: Canonical output location
Handoff SHALL write the document exclusively to `<working-dir>/.sessionkit/HANDOFF.md`. Handoff MUST NOT write the document to any other path.

#### Scenario: Document written
- **WHEN** synthesis completes
- **THEN** the document is at `.sessionkit/HANDOFF.md` in the current working directory

### Requirement: Completion report
After writing, Handoff SHALL report the absolute file path and suggest running `/pickup` to resume.

#### Scenario: Handoff confirmed
- **WHEN** the document is written
- **THEN** Handoff reports the absolute path and suggests `/pickup`
