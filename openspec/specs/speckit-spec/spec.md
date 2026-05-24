# speckit-spec

## Purpose

Orchestrate the full discuss → interview → plan → file workflow for a bug, fix, or feature. Interviews the user, builds a structured plan, and files it as a GitHub epic with linked child issues.

## Requirements

### Requirement: Codebase Context Exploration
Before the first interview question, the skill SHALL search for files relevant to `$ARGUMENTS` to ground the interview in actual code. This search runs in the background without blocking the first question batch.

#### Scenario: Relevant files fetched before plan is written
- **WHEN** `$ARGUMENTS` references a codebase area
- **THEN** grep or glob results are collected before the plan is written in step 3

### Requirement: Simple vs. Full Path Classification
The skill SHALL classify the request as simple (single cohesive change, single file or tightly co-located files) or full (multiple conceptual changes or files spanning unrelated modules). Classification is narrated inline when confident; `AskUserQuestion` fires only when the heuristic is ambiguous.

#### Scenario: Clearly simple path narrated and short-circuited
- **WHEN** both heuristic tests pass unambiguously
- **THEN** the skill narrates the classification inline and runs the simple path without calling `AskUserQuestion` for routing

#### Scenario: Clearly full path narrated and falls through to interview
- **WHEN** at least one heuristic test fails unambiguously
- **THEN** the skill narrates the classification inline and invokes `speckit:interview`

#### Scenario: Ambiguous path asks user once
- **WHEN** the heuristic is uncertain
- **THEN** the skill calls `AskUserQuestion` once with options Simple path, Full interview, and Cancel

#### Scenario: Simple path files one issue without epic
- **WHEN** the simple path is selected or approved
- **THEN** the skill files one standalone issue via `/catalog` with no `--epic` flag, skips epic creation, and jumps to the report step

### Requirement: Epic Slug Derivation
For plans with 2 or more tasks, the skill SHALL derive a short kebab-case slug from the epic title, capped at 30 characters after the `epic:` prefix. The user reviews and may edit the slug during plan approval.

#### Scenario: Slug derived from epic title
- **WHEN** the plan will produce an epic
- **THEN** the slug is lowercase kebab-case with filler words stripped and at most 30 characters after the `epic:` prefix

#### Scenario: Slug omitted for single-issue plans
- **WHEN** the plan produces only one task
- **THEN** no `## Epic label` section appears in the plan

### Requirement: Plan Approval Gate
The skill SHALL present the plan and an `AskUserQuestion` approval call in the same assistant turn. Ending the turn after the plan without the tool call is a defect.

#### Scenario: Full-path plan and approval call in same turn
- **WHEN** the full-path plan is ready
- **THEN** the plan markdown and an `AskUserQuestion` call appear in the same turn with options: Approve and file issues, Condense to single issue, Adjust plan, Cancel

#### Scenario: Simple-path plan and approval call in same turn
- **WHEN** the simple-path plan is ready
- **THEN** the plan markdown and an `AskUserQuestion` call appear in the same turn with options: Approve and file, Run full interview instead, Adjust, Cancel

#### Scenario: Task tracking created on full-path approval
- **WHEN** the user approves a full-path plan
- **THEN** the skill creates tasks for file-children, create-epic-tracking-issue, wire-sub-issues, wire-blocked-by-edges, and final-report before invoking `/catalog`

### Requirement: Child Issue Filing
The skill SHALL pass the full task list to `/catalog` with `--epic <slug>` and advance to epic creation immediately after `/catalog` returns, without waiting for user input.

#### Scenario: Catalog invoked with epic flag
- **WHEN** a full-path plan is approved
- **THEN** `/catalog` is invoked with `--epic <slug>` and the complete task list

#### Scenario: Orchestrator advances after catalog returns
- **WHEN** `/catalog` returns the issue table
- **THEN** the skill proceeds to epic tracking issue creation without pausing

### Requirement: Epic Tracking Issue Creation
After all child issues are filed, the skill SHALL create one parent epic issue with title `epic: <description>`, labels `epic`, `epic:<slug>`, and `priority:<highest-child-priority>`. Child issues are linked as GitHub sub-issues, not via checklist.

#### Scenario: Epic issue created after all children
- **WHEN** all child issues have been filed
- **THEN** the skill creates the epic tracking issue with the three required labels

#### Scenario: Epic label provisioned before creation
- **WHEN** the `epic:<slug>` label does not exist
- **THEN** the skill creates it with color `#5319e7` before invoking `gh issue create`

#### Scenario: Existing epic label requires confirmation
- **WHEN** the `epic:<slug>` label already exists
- **THEN** the skill asks the user via `AskUserQuestion` before reusing it

#### Scenario: Children attached as sub-issues
- **WHEN** the epic tracking issue is created
- **THEN** each child is added via the GitHub sub-issues API using the child's numeric `id`

### Requirement: Blocked-By Edge Wiring
For each task with a `Depends On` value in the plan, the skill SHALL set the corresponding GitHub blocked-by relationship using the sub-issues API.

#### Scenario: Blocked-by edges wired for dependent tasks
- **WHEN** a task's `Depends On` column references another task
- **THEN** the skill calls the GitHub blocked-by API to wire the relationship between the two issue IDs

#### Scenario: No-dependency plan skips wiring
- **WHEN** no tasks have `Depends On` values
- **THEN** the wire-blocked-by-edges step completes immediately with no API calls

### Requirement: Team-Readiness Assessment
For full-path epics, the skill SHALL assess whether the work is suited for parallel agent-team execution using four signals. When at least three signals hold, the skill re-decomposes issues by phase and posts a dispatch summary as a comment on the epic.

#### Scenario: Team-suitable spec gets phase labels and dispatch comment
- **WHEN** at least three of the four suitability signals hold
- **THEN** the skill provisions phase labels, assigns each child to a phase, and posts a team dispatch summary comment on the epic issue

#### Scenario: Non-team-suitable spec prints skip line
- **WHEN** fewer than three suitability signals hold
- **THEN** the skill prints a single-line skip message with the reason and proceeds to the report step

### Requirement: Pre-End Self-Check
Before ending any turn while the skill is the active orchestrator, the skill SHALL check the task list. If any task is pending or in-progress, the skill SHALL execute the next task rather than ending the turn.

#### Scenario: Pending tasks prevent turn end
- **WHEN** the skill considers ending a turn and a task is pending or in-progress
- **THEN** the skill executes the next task instead of ending the turn

#### Scenario: All tasks completed allows turn end
- **WHEN** all tracked tasks are completed
- **THEN** the skill ends the turn after the report step
