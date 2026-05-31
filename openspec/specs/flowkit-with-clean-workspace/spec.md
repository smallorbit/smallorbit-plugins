# With Clean Workspace

## Purpose
With Clean Workspace wraps a command whose side effects include an implicit `git pull` (most notably `gh pr merge --squash --delete-branch` / `--merge --delete-branch`) so a dirty workspace cannot break the post-merge pull with errors such as `cannot pull with rebase: You have unstaged changes`. It auto-stashes uncommitted changes around the wrapped command and restores them afterward. It is a sub-skill used by merge-pr and release.

## Requirements

### Requirement: Wrapped-command interface
With Clean Workspace SHALL accept the command to run via a `-- <command> [args...]` interface. It MUST execute the deterministic stash-guard behavior through its `scripts/with_clean_workspace.sh` script rather than re-implementing stash logic inline. When the `--` separator or the command is missing, the skill MUST exit with code `2` and emit usage text to stderr.

#### Scenario: Command provided after separator
- **WHEN** the skill is invoked as `-- <command> [args...]`
- **THEN** it runs the deterministic stash-guard around the provided command

#### Scenario: Missing separator or command
- **WHEN** the `--` separator or the wrapped command is absent
- **THEN** the skill exits with code `2`
- **AND** it writes usage text to stderr

#### Scenario: Cross-skill invocation
- **WHEN** another flowkit skill such as merge-pr or release invokes this skill
- **THEN** the caller derives the with-clean-workspace skill path from its own location and runs `scripts/with_clean_workspace.sh` with the `-- <command>` contract

### Requirement: Auto-stash dirty workspace
With Clean Workspace SHALL stash both tracked and untracked uncommitted changes before running the wrapped command, using a stash that includes untracked files and a recognizable label, so the wrapped command's implicit pull operates against a clean workspace.

#### Scenario: Dirty workspace before wrapped command
- **WHEN** the workspace has uncommitted tracked or untracked changes
- **THEN** the skill stashes the tracked and untracked changes with the auto-stash label before invoking the wrapped command

### Requirement: Restore on success
On successful completion of the wrapped command, With Clean Workspace SHALL restore the previously stashed changes by popping the auto-stash.

#### Scenario: Wrapped command succeeds and stash restores cleanly
- **WHEN** the wrapped command exits successfully
- **AND** the stash can be popped without conflict
- **THEN** the skill pops the auto-stash, restoring the previously uncommitted changes

### Requirement: Preserve stash on pop conflict
When restoring the stash produces a conflict, With Clean Workspace SHALL leave the stash on the stack rather than discarding it, and SHALL warn to stderr so the operator can resolve it manually.

#### Scenario: Stash pop conflicts after wrapped command
- **WHEN** the wrapped command succeeds but popping the auto-stash conflicts
- **THEN** the skill leaves the stash on the stack
- **AND** it warns to stderr

### Requirement: Preserve stash and propagate exit code on failure
When the wrapped command exits non-zero, With Clean Workspace SHALL keep the stash intact, warn to stderr, and exit with the wrapped command's non-zero exit code.

#### Scenario: Wrapped command fails
- **WHEN** the wrapped command exits with a non-zero status
- **THEN** the skill keeps the stash on the stack
- **AND** it warns to stderr
- **AND** it exits with the wrapped command's non-zero exit code
