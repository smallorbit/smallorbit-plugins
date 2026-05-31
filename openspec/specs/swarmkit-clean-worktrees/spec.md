# Clean Worktrees

## Purpose

Remove all agent worktrees and their orphaned local branches (those under the `worktree-agent-*` prefix) left behind by a swarm run. It is a sub-skill invoked by swarm for post-run cleanup, operates only on local state, and defers remote branch cleanup to the companion remote-cleanup skill.

## Requirements

### Requirement: Gather state before removal

The skill SHALL first enumerate what would be removed by gathering current git state, and SHALL surface the error and stop if gathering fails. The gathered state SHALL identify the caller's branch, the main worktree path, the agent worktrees to remove, the orphaned local branches to delete, and any branches still checked out by active worktrees.

#### Scenario: Gather succeeds

- **WHEN** the skill is invoked
- **THEN** it gathers the caller branch, main worktree path, worktrees to remove, branches to delete, and any stuck worktrees before taking any destructive action

#### Scenario: Gather fails

- **WHEN** the gather step exits non-zero
- **THEN** the skill surfaces the error output and stops without removing anything

### Requirement: Refuse to delete branches held by active worktrees

The skill SHALL NOT proceed to removal when any branch is still checked out by an active worktree, and MUST report which branches are blocked and instruct the operator to remove or force-stop those worktrees before re-running.

#### Scenario: Stuck worktree detected

- **WHEN** the gathered state reports one or more branches still checked out by active worktrees
- **THEN** the skill stops immediately, lists each blocked branch, and instructs the operator to remove or force-stop those worktrees before re-running

### Requirement: No-op when nothing to clean

The skill SHALL detect when there are no agent worktrees to remove and no orphaned branches to delete, and in that case SHALL report that there is nothing to clean and stop without taking destructive action.

#### Scenario: Nothing to clean

- **WHEN** both the worktrees-to-remove list and branches-to-delete list are empty
- **THEN** the skill reports that no agent worktrees or orphaned branches were found and stops

### Requirement: Remove worktrees and delete orphaned branches

When there is work to do and no stuck worktrees, the skill SHALL remove the gathered agent worktrees and delete the gathered orphaned local branches, passing the main worktree path and caller branch so the removal can run safely. If the removal step exits non-zero, the skill SHALL surface the error and stop.

#### Scenario: Removal succeeds

- **WHEN** there are worktrees or branches to clean and no stuck worktrees
- **THEN** the skill removes the listed worktrees and deletes the listed orphaned local branches

#### Scenario: Removal fails

- **WHEN** the removal step exits non-zero
- **THEN** the skill surfaces the error output and stops

#### Scenario: Caller cwd inside a target worktree

- **WHEN** the caller's current working directory is inside one of the worktrees listed for removal
- **THEN** the removal refuses with operator guidance to exit the worktree first

### Requirement: Local-only scope

The skill SHALL operate only on local worktrees and local branches and SHALL NOT delete remote branches; remote `worktree-agent-*` branch cleanup is delegated to the separate remote-cleanup skill.

#### Scenario: Remote branches present

- **WHEN** remote `worktree-agent-*` branches exist
- **THEN** the skill leaves them untouched and limits its actions to local worktrees and branches

### Requirement: Report outcome and caller-branch restoration

After removal the skill SHALL report a summary including the count and list of worktrees removed, the count and list of branches deleted, the caller-branch restoration status, and any removal or branch errors. When the caller's branch was itself removed during cleanup and no errors occurred, the skill SHALL warn that there is no branch to restore to.

#### Scenario: Summary after successful cleanup

- **WHEN** removal completes
- **THEN** the skill reports the worktrees removed, branches deleted, caller-branch restoration status, and any errors

#### Scenario: Caller branch was removed

- **WHEN** the caller's branch was removed as part of cleanup and there were no errors
- **THEN** the skill warns that the caller branch was removed and there is no branch to restore to
