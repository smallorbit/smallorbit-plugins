# Pickup

## Purpose
Pickup loads `.sessionkit/HANDOFF.md` at the start of a new session, orients the agent by summarizing its contents, hydrates the task list from the snapshot, checks for branch mismatches, and asks what to tackle first. It is the complement to Handoff.

## Requirements

### Requirement: Model dispatch
Pickup SHALL execute entirely within a Haiku-class sub-agent regardless of the parent session's active model. The outer invocation tier is a thin dispatcher that locates `.sessionkit/HANDOFF.md` and spawns the sub-agent with all instructions inline as a self-contained prompt — it MUST NOT reference the skill by name (which would cause infinite re-dispatch). All file reads, parsing, task hydration, and orientation output occur inside the sub-agent.

#### Scenario: Invoked on any model
- **WHEN** Pickup is invoked from a session running any model (Opus, Sonnet, or Haiku)
- **THEN** the actual execution occurs inside a Haiku sub-agent; the parent session's model does not perform any pickup work beyond the initial dispatch

### Requirement: Graceful absent-file handling
Pickup SHALL check for `.sessionkit/HANDOFF.md` before proceeding. If the file does not exist, Pickup MUST report the absence and stop — it MUST NOT attempt to orient, hydrate tasks, or ask what to do next.

#### Scenario: Handoff file absent
- **WHEN** `.sessionkit/HANDOFF.md` does not exist
- **THEN** Pickup reports the file is missing with a guidance message and stops

#### Scenario: Handoff file present
- **WHEN** `.sessionkit/HANDOFF.md` exists
- **THEN** Pickup reads and parses it, then continues with the remaining steps

### Requirement: Open-ended section parsing
Pickup SHALL parse all standard sections (Project, Date, Branch, Goal, Progress, Git State, Remaining Work, Context). Unknown headings SHALL be silently ignored — section parsing is open-ended. Legacy section names from prior versions SHALL not cause errors.

#### Scenario: Unknown heading encountered
- **WHEN** the handoff file contains a heading not in the standard section list
- **THEN** Pickup ignores it without error and continues parsing

### Requirement: Orientation summary
Pickup SHALL produce a structured orientation summary from the parsed content. The summary SHALL cover: Goal (restated clearly), Progress (what was done and decided), Git State (branch, staged/unstaged, recent commits), Remaining Work (in priority order), and Context (gotchas and notes). The summary SHALL be concise — it MUST NOT reproduce the document verbatim.

#### Scenario: Orientation presented
- **WHEN** the handoff file is successfully parsed
- **THEN** Pickup outputs a structured summary covering all five areas without reproducing the document verbatim

### Requirement: Task list hydration — two-pass
Pickup SHALL locate the fenced `json` block following `## Task List`. If the block is absent or unparseable, Pickup SHALL emit one line noting the skip and continue. For tasks with `status` `pending` or `in_progress`, Pickup SHALL create new tasks via `TaskCreate` (pass 1), record old-ID → new-ID mappings, then restore `blockedBy` edges via `TaskUpdate` using remapped IDs (pass 2). Completed tasks SHALL be skipped. Pickup MUST NOT wire the `blocks` direction — only `blockedBy`.

#### Scenario: Task list present and parseable
- **WHEN** `## Task List` contains a valid JSON array
- **THEN** Pickup creates tasks for `pending`/`in_progress` entries (pass 1), then wires `blockedBy` using remapped IDs (pass 2)

#### Scenario: Task list absent or unparseable
- **WHEN** the JSON block is missing or cannot be parsed
- **THEN** Pickup emits "No task list snapshot — skipping hydration" and continues to step 5

#### Scenario: Completed tasks skipped
- **WHEN** a task in the snapshot has `status: completed`
- **THEN** Pickup skips creating that task — it is surfaced only in the orientation summary

### Requirement: Branch mismatch detection
Pickup SHALL compare the handoff branch against the current branch. If they differ, Pickup MUST suggest the checkout command. Pickup MUST NOT switch branches automatically.

#### Scenario: Branch matches
- **WHEN** the current branch matches the handoff branch
- **THEN** Pickup makes no branch suggestion

#### Scenario: Branch mismatch
- **WHEN** the current branch differs from the handoff branch
- **THEN** Pickup suggests `git checkout <branch-from-handoff>` and does not switch automatically

### Requirement: Readiness confirmation via structured prompt
Pickup SHALL end by asking the user what to tackle first via `AskUserQuestion`. The question SHALL reference the handoff Goal. Options SHALL be derived from the top items in Remaining Work (highest-priority first), up to four options. If fewer than two actionable items exist in Remaining Work, Pickup SHALL fall back to plain text.

#### Scenario: Multiple remaining items
- **WHEN** Remaining Work has two or more actionable items
- **THEN** Pickup presents them as structured options via `AskUserQuestion`

#### Scenario: Fewer than two actionable items
- **WHEN** Remaining Work has fewer than two actionable items
- **THEN** Pickup asks what to do next in plain text

### Requirement: Read-only operation
Pickup SHALL NOT modify `.sessionkit/HANDOFF.md` under any circumstances. Pickup MUST NOT re-execute commands referenced in the handoff.

#### Scenario: Handoff file untouched
- **WHEN** Pickup runs to completion
- **THEN** `.sessionkit/HANDOFF.md` is byte-identical to when Pickup started
