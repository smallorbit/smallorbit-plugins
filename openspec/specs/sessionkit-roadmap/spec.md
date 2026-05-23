# Roadmap

## Purpose
Roadmap surveys the current work-in-flight, synthesizes a linear task chain that takes the work to its natural completion state, presents it for user approval, and then either hands it off to Drive for autonomous execution or returns it for manual execution.

## Requirements

### Requirement: Read-only survey
During planning, Roadmap SHALL only read — it MUST NOT mutate the repository, branches, tags, or PRs during steps 1 through 3. Work-in-flight signals collected SHALL include: uncommitted state, branch/upstream relationship, open PRs (current branch and peers), epic mode configuration, release pipeline state (RC branches, latest tag), in-flight worktrees, and existing tasks.

#### Scenario: Survey phase
- **WHEN** Roadmap is invoked
- **THEN** all survey commands run in parallel and no mutations occur before the plan is approved

### Requirement: State classification
Roadmap SHALL identify every applicable state signal and map each to a sub-chain entry point. Signals are composable — multiple may apply simultaneously. The canonical signals include: uncommitted changes, local commits ahead of upstream, pushed branch with no PR, open PR for current branch, peer PRs on the same base, epic mode active, develop ahead of main, RC branch exists, and nothing-to-ship state.

#### Scenario: Multiple signals apply
- **WHEN** more than one state signal is present (e.g. uncommitted changes AND an open peer PR)
- **THEN** each signal contributes its sub-chain entry point to the composed plan

#### Scenario: Nothing to ship
- **WHEN** the latest release is shipped and develop is in sync with main
- **THEN** Roadmap surfaces the nothing-to-ship state and offers alternatives instead of an empty plan

### Requirement: Task chain synthesis
Roadmap SHALL compose the sub-chains into a single ordered task chain. Each task SHALL have an imperative subject, an unambiguous description (exact skill invocation or concrete outcome), an `activeForm` label, and `blockedBy` wiring to its predecessor. Roadmap SHALL use named skills in task descriptions where available, not raw command pastes.

#### Scenario: Linear chain produced
- **WHEN** the state signals compose into a sequential plan
- **THEN** tasks are created with `blockedBy` wiring so each step is unblocked only after its predecessor completes

#### Scenario: Named skill available
- **WHEN** a step maps to a known installed skill
- **THEN** the task description references the skill by name (e.g. "Run `/flowkit:merge-pr`")

### Requirement: Single-thread planning
Roadmap SHALL plan one work thread per invocation. If the survey reveals two unrelated in-flight threads, Roadmap MUST ask the user which to plan and defer the other.

#### Scenario: Two unrelated threads found
- **WHEN** the survey reveals e.g. an in-flight PR and a separate untracked feature branch
- **THEN** Roadmap asks which thread to plan and does not produce a forked plan

### Requirement: Plan presentation and approval gate
Roadmap SHALL present the plan as a compact summary before creating any tasks, then present it for approval via `AskUserQuestion`. Options SHALL include: drive autonomously (recommended), drive manually, modify, and cancel. Tasks created before approval are provisional — if the user cancels, Roadmap MUST delete every task created in that invocation.

#### Scenario: Approval requested
- **WHEN** the plan is ready
- **THEN** Roadmap outputs the plan summary and calls `AskUserQuestion` with the four approval options

#### Scenario: User approves and drives
- **WHEN** the user selects "Drive it for me"
- **THEN** Roadmap invokes `/sessionkit:drive` immediately and exits

#### Scenario: User approves manually
- **WHEN** the user selects "I'll drive"
- **THEN** Roadmap prints the task IDs and a one-line reminder, then exits

#### Scenario: User modifies
- **WHEN** the user selects "Modify"
- **THEN** Roadmap prompts for changes, updates the task list, and re-presents from the plan summary step

#### Scenario: User cancels
- **WHEN** the user selects "Cancel"
- **THEN** Roadmap deletes every task it created and exits

### Requirement: Canonical release sequence
When an epic is in flight (open worktree-agent-* PRs targeting a feature branch), Roadmap SHALL include the canonical bubble-free sequence: merge-stack → verify → ship-epic → ship. Roadmap MUST NOT collapse this into a single step.

#### Scenario: Epic in flight
- **WHEN** open worktree-agent-* PRs target the current feature branch
- **THEN** the plan includes merge-stack, a manual verify step, ship-epic, and ship — in that order
