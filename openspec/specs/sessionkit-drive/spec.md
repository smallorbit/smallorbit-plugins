# Drive

## Purpose
Drive executes an approved task chain autonomously from start to finish. It manages task state throughout, surfaces to the user only for blockers or executive decisions, and produces a final report on completion.

## Requirements

### Requirement: Pre-flight chain validation
Drive SHALL verify a runnable chain exists before starting. If no `pending` or `in_progress` tasks exist, Drive MUST stop and report that the task list is empty. If all tasks have unresolved `blockedBy` edges pointing at non-existent IDs, Drive MUST report the broken state and stop.

#### Scenario: Task list is empty
- **WHEN** `TaskList` returns no `pending` or `in_progress` tasks
- **THEN** Drive stops with a message directing the user to add tasks or run `/sessionkit:roadmap`

#### Scenario: Broken dependency graph
- **WHEN** all pending tasks have `blockedBy` entries referencing non-existent task IDs
- **THEN** Drive reports the broken state and stops without starting any work

### Requirement: Single driving preamble
Drive SHALL emit exactly one short preamble before the first tool call, stating the starting task ID and the driving contract. Drive MUST NOT narrate individual task progress beyond that initial preamble.

#### Scenario: Driving starts
- **WHEN** a runnable chain is confirmed
- **THEN** Drive emits one preamble (starting task, silence contract, Esc-to-interrupt note) and then works silently

### Requirement: Task-state discipline
For each task, Drive SHALL mark it `in_progress` before doing any work, and `completed` immediately after the outcome is achieved. Drive MUST NOT have more than one task in `in_progress` at a time. Drive MUST NOT batch completions.

#### Scenario: Task lifecycle
- **WHEN** Drive picks a task to execute
- **THEN** `in_progress` is set before the first tool call for that task, and `completed` is set as soon as the outcome is achieved — never deferred

#### Scenario: Multiple in_progress tasks
- **WHEN** multiple tasks are found in `in_progress` state at loop entry
- **THEN** Drive finishes them before picking any new pending task

### Requirement: Task selection order
Drive SHALL pick the lowest-ID `pending` task whose `blockedBy` array is empty or fully completed. Drive MUST NOT start a task whose blockers are unresolved.

#### Scenario: Next unblocked task
- **WHEN** multiple pending tasks exist
- **THEN** Drive picks the lowest-ID task with no unresolved `blockedBy` dependencies

### Requirement: Task execution dispatch
Drive SHALL dispatch each task according to its description. A description referencing a skill SHALL be invoked via the skill tool. A description giving a shell command SHALL be run via the shell. An open-ended outcome description SHALL be executed using whatever tools fit the described outcome.

#### Scenario: Named skill task
- **WHEN** a task description references a skill (e.g. "Run `/flowkit:merge-pr`")
- **THEN** Drive invokes that skill, passing any arguments mentioned in the description

#### Scenario: Shell command task
- **WHEN** a task description provides an explicit shell command
- **THEN** Drive runs that command via the shell

#### Scenario: Outcome-based task
- **WHEN** a task description states an outcome without specifying a skill or command
- **THEN** Drive uses any appropriate tools to achieve the described outcome

### Requirement: Controlled surface conditions
Drive SHALL surface to the user only for blockers, executive decisions, risky actions, or completion. Drive MUST NOT surface for routine failures with obvious remediation, cosmetic choices, or "just to confirm" moments.

#### Scenario: Unrecoverable blocker
- **WHEN** a tool fails in a way Drive cannot recover from (auth missing, network down, irreversible state required)
- **THEN** Drive emits plain text describing the failure, leaves the task `in_progress`, and stops

#### Scenario: Executive decision required
- **WHEN** a genuine fork in approach emerges that the task description does not resolve
- **THEN** Drive presents options via `AskUserQuestion` with a recommendation, then resumes on the user's answer

#### Scenario: Risky or destructive action
- **WHEN** the next step would delete data, force-push, rewrite shared history, or send messages on the user's behalf
- **THEN** Drive presents a plain-text confirmation prompt before proceeding — not an `AskUserQuestion`

### Requirement: Scope integrity
Drive SHALL NOT silently expand scope beyond the task list. If a task requires sub-work not in the plan, Drive MUST create a visible task via `TaskCreate` with appropriate `blockedBy` rather than absorbing the work into an existing task. Drive MUST NOT modify task subjects or descriptions to make them easier.

#### Scenario: Unplanned sub-work discovered
- **WHEN** executing a task reveals necessary work not in the plan
- **THEN** Drive creates a new task (with `blockedBy` wiring) and surfaces it as an executive decision if scope is affected

### Requirement: Final report
Drive SHALL emit a tight completion report when the chain is fully done. The report SHALL list artifacts produced (PR URLs, tags, files modified) and any outstanding items the user should know about. Drive MUST NOT reproduce the task list verbatim in the report.

#### Scenario: Chain completed
- **WHEN** no `pending` or `in_progress` tasks remain
- **THEN** Drive emits a report with task count, elapsed time, artifact highlights, and any outstanding items
