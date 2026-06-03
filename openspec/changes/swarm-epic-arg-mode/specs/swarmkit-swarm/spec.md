## MODIFIED Requirements

### Requirement: Epic mode resolution

The skill SHALL compute whether to run in epic mode before any setup work, and when epic mode is on it MUST cut or resume a single epic feature branch that all PRs target. For the one-shot single-argument case, the skill SHALL consult epic membership (the epic/sub-issue expansion already performed by issue gathering) before finalizing the mode, so that a single argument which is an epic expanding to multiple children enables epic mode rather than being treated as a standalone issue.

#### Scenario: Epic mode is disabled

- **WHEN** `--base` is set, OR `--no-epic` is set, OR the run is one-shot with exactly one issue that is a standalone (non-epic) issue
- **THEN** epic mode SHALL be off, no epic branch is cut, and PRs target the base branch directly

#### Scenario: Single epic argument enables epic mode

- **WHEN** the run is one-shot with exactly one argument and that argument is an epic that expands to two or more wired child issues, and neither `--base` nor `--no-epic` is set
- **THEN** epic mode SHALL be on, the skill SHALL resolve an epic branch name of the form `feature/<slug>-<N>` (slug derived from the epic or its lowest-numbered child) and cut it, and the expanded children SHALL be stacked/targeted under that branch

#### Scenario: Single epic argument with too few or unwired children stays flat

- **WHEN** the run is one-shot with a single epic argument that has fewer than two wired child issues, or whose children are not wired via the sub-issue API
- **THEN** epic mode SHALL be off (there is no stack to isolate), and the existing unwired-epic announcement applies when children are unwired

#### Scenario: Epic mode is enabled

- **WHEN** none of the disabling conditions hold
- **THEN** epic mode SHALL be on and the skill SHALL resolve an epic branch name of the form `feature/<slug>-<N>` or `feature/<slug>-<date>` and cut it from the default branch

#### Scenario: Resuming an existing epic branch

- **WHEN** the resolved epic branch already exists on the remote
- **THEN** the skill SHALL fetch and check it out instead of recreating it, and refresh the pinned base configuration

#### Scenario: Conflicting pinned epic guard

- **WHEN** the preflight is invoked to scope the pinned base and a pinned base is already set to a different epic branch (one starting with `feature/`) than the one about to be pinned
- **THEN** the preflight SHALL refuse to run, exit non-zero, and instruct the operator to pass `--no-epic` or reuse the pinned slug — the guard is enforced in the preflight script so any direct caller is protected

#### Scenario: Empty board at loop entry

- **WHEN** epic mode is on in loop mode and the board is clear at entry
- **THEN** the skill SHALL defer cutting the epic branch until a cycle selects at least one issue, and if the board stays clear it announces the board is clear and exits without cutting a branch
