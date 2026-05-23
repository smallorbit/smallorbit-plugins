# Handoff

## Purpose
Handoff captures the current session's goal, progress, git state, task list, remaining work, and key context into `.sessionkit/HANDOFF.md` so another agent can resume the work without losing momentum. It minimizes cost by reusing unchanged sections from a prior handoff via fingerprint-based caching.

## Requirements

### Requirement: Context collection
Handoff SHALL gather git state (HEAD SHA, branch, staged files, unstaged files, recent commits) and task list in parallel before synthesizing the document.

#### Scenario: Context gathered
- **WHEN** Handoff is invoked
- **THEN** git state and task list are collected in parallel before any synthesis begins

### Requirement: Fingerprint-based section reuse
Handoff SHALL compute a `gitFingerprint` (HEAD SHA + sorted staged/unstaged file hashes) and a `taskFingerprint` (SHA-1 of the canonicalized task list JSON). Each fingerprint governs its own pair of sections independently: `gitFingerprint` controls `## Git State` and `## Progress`; `taskFingerprint` controls `## Task List` and `## Remaining Work`. Sections whose fingerprint matches the prior header SHALL be reused byte-for-byte. `## Goal` and `## Context` SHALL always be regenerated.

#### Scenario: Git fingerprint matches
- **WHEN** the prior handoff's `gitFingerprint` matches the current one
- **THEN** `## Git State` and `## Progress` are reused verbatim; only `## Goal` and `## Context` are regenerated

#### Scenario: Task fingerprint matches
- **WHEN** the prior handoff's `taskFingerprint` matches the current one
- **THEN** `## Task List` and `## Remaining Work` are reused verbatim

#### Scenario: Both fingerprints match
- **WHEN** both fingerprints match the prior header
- **THEN** all four reusable sections come straight from the prior file and no sub-agent is dispatched

### Requirement: Routing to delta or full path
Handoff SHALL use the delta path when all four conditions hold: a prior HANDOFF.md parsed cleanly, the prior HEAD is an ancestor of the current HEAD, at most two reusable sections need regeneration, and `--full` is not present. Otherwise Handoff SHALL use the full regenerate path.

#### Scenario: Delta path selected
- **WHEN** all four delta-mode conditions hold
- **THEN** Handoff surgically edits the existing file in place without dispatching a sub-agent

#### Scenario: Full path selected
- **WHEN** any delta-mode condition fails or `--full` is passed
- **THEN** Handoff dispatches a sub-agent for full synthesis

### Requirement: Document structure
The handoff document SHALL follow a fixed section order: meta header → Goal → Progress → Git State → Remaining Work → Task List → Context. All content in Progress, Remaining Work, and Context SHALL be bullets only — no narrative paragraphs. The meta header SHALL be the first line and SHALL contain both fingerprints.

#### Scenario: Section order
- **WHEN** a handoff document is written (delta or full)
- **THEN** sections appear in the canonical order: Goal → Progress → Git State → Remaining Work → Task List → Context

#### Scenario: Bullet-only sections
- **WHEN** Progress, Remaining Work, or Context content is generated
- **THEN** every entry is a bullet — no narrative paragraphs

### Requirement: Task list serialization
The `## Task List` section SHALL contain a single fenced `json` code block. Each task object SHALL include only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, and `blocks`. Deleted tasks SHALL be excluded. The original task `id` SHALL be preserved so `/pickup` can wire `blockedBy` relationships.

#### Scenario: Task list in JSON block
- **WHEN** the document is written
- **THEN** `## Task List` contains a fenced `json` block with one object per non-deleted task, using the original task IDs

### Requirement: Sub-agent synthesis
When the full path is selected, Handoff SHALL delegate document synthesis to a Haiku-class sub-agent. If the sub-agent call fails or returns output missing `## Task List`, Handoff SHALL fall back to inline synthesis and prepend a warning comment to the document.

#### Scenario: Sub-agent succeeds
- **WHEN** the full path is selected and the sub-agent returns a valid document
- **THEN** the synthesized document is written to disk

#### Scenario: Sub-agent fails
- **WHEN** the sub-agent call fails or returns output missing `## Task List`
- **THEN** Handoff synthesizes the document inline and prepends `<!-- handoff-warning: haiku sub-agent unavailable, synthesized in-line -->`

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
After writing, Handoff SHALL report the absolute file path, the chosen mode (delta or full), which sections were regenerated vs. reused, and suggest running `/pickup` to resume.

#### Scenario: Handoff confirmed
- **WHEN** the document is written
- **THEN** Handoff reports the path, mode, section reuse outcome, and suggests `/pickup`
