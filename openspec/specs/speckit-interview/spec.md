# speckit-interview

## Purpose

Conduct a deep, structured interview to think through a feature, bug, or change. Produces a structured plan ready to feed into `/spec` or `/catalog`.

## Requirements

### Requirement: Input Handling
The skill SHALL accept a freeform description via `$ARGUMENTS`. When `$ARGUMENTS` is empty, the skill SHALL ask the user what they want to think through before proceeding.

#### Scenario: Description provided via arguments
- **WHEN** `$ARGUMENTS` contains a freeform description
- **THEN** the skill uses it as the starting context for the interview

#### Scenario: Empty arguments prompts for topic
- **WHEN** `$ARGUMENTS` is empty
- **THEN** the skill asks the user what they want to work through before forming interview questions

### Requirement: Codebase Grounding
When `$ARGUMENTS` references files or areas of the codebase, the skill SHALL search for relevant files to ground interview questions in actual code. This search runs in the background while forming the first question batch.

#### Scenario: Relevant files fetched in background
- **WHEN** `$ARGUMENTS` references codebase areas or files
- **THEN** the skill greps or globs for relevant files without waiting for results before asking the first questions

### Requirement: Multi-Round Interview
The skill SHALL use `AskUserQuestion` to probe scope, behaviour, constraints, decisions, and acceptance criteria. Each round SHALL contain 1–4 questions. The skill SHALL challenge inconsistencies, assumptions, and contradictions and continue rounds until the plan is unambiguous.

#### Scenario: Questions sent 1–4 per round
- **WHEN** the skill is gathering information
- **THEN** each `AskUserQuestion` call contains between 1 and 4 questions, never a single question alone and never more than 4

#### Scenario: Interview continues until unambiguous
- **WHEN** a round's answers leave ambiguities unresolved
- **THEN** the skill asks a follow-up round rather than producing the plan

#### Scenario: Inconsistencies challenged directly
- **WHEN** the user's answers contain a contradiction or unsupported assumption
- **THEN** the skill calls it out directly before moving to the next dimension

### Requirement: Structured Plan Production
The skill SHALL synthesise the interview into a plan with exactly these sections in order: Goal, Background, Requirements, Out of Scope, Tasks. The Tasks section SHALL use a table with columns: #, Title, Category, Priority, Depends On, Description.

#### Scenario: Plan contains all five required sections
- **WHEN** the interview is complete
- **THEN** the produced plan contains Goal, Background, Requirements, Out of Scope, and Tasks sections in that order

#### Scenario: Documentation task appended unless pure refactor
- **WHEN** the plan is not a pure refactor or internal-only change
- **THEN** an "Update documentation" task is appended as the final row in the Tasks table

#### Scenario: Tasks table includes Depends On column
- **WHEN** the Tasks table is rendered
- **THEN** every row includes a Depends On value (`—` when none)

### Requirement: Silent Task Consolidation
Before presenting the Tasks table, the skill SHALL run a silent consolidation pass that merges over-decomposed tasks. The user sees only the consolidated result.

#### Scenario: Same-file same-change tasks merged
- **WHEN** two tasks touch only the same single file and address related changes to the same function or section
- **THEN** they are merged into one task with both originals preserved as sub-bullets

#### Scenario: Strict-ordering no-standalone-value tasks merged
- **WHEN** one task cannot ship without another and provides no independent acceptance criteria
- **THEN** the two tasks are merged

#### Scenario: Soft cap re-examination when task count exceeds four
- **WHEN** after the main consolidation pass the task count is still greater than 4
- **THEN** a second pass re-examines under looser merge signals until no further defensible merges remain

#### Scenario: Priority and category resolved deterministically on merge
- **WHEN** two tasks are merged
- **THEN** the merged task takes the higher priority and higher-impact category, and remaps dependencies accordingly

### Requirement: Handoff Behaviour
When invoked as a sub-skill, the skill SHALL output only the structured plan with no trailing prose. When invoked standalone, the skill SHALL state that the plan is ready to feed into `/speckit:catalog`.

#### Scenario: Sub-skill invocation produces plan only
- **WHEN** the skill is invoked as a sub-skill by an orchestrator
- **THEN** the response ends at the Tasks table with no trailing sentence, next-steps paragraph, or hand-off prose

#### Scenario: Standalone invocation states catalog handoff
- **WHEN** the skill is invoked directly via `/interview`
- **THEN** the response ends by stating the plan is ready to feed into `/speckit:catalog`
