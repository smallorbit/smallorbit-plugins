# Clean Remote Worktrees

## Purpose

Sweep orphaned remote `worktree-agent-*` branches left behind on the origin after swarm runs. A branch is safe to delete only when its most-recent pull request is merged. This skill never touches local state; it is the remote counterpart to clean-worktrees.

## Requirements

### Requirement: Inputs and Modes

The skill SHALL run with no required inputs and SHALL support exactly two modes: an interactive default with no arguments, and a non-interactive mode selected by `--yes`.

#### Scenario: No arguments supplied (interactive)

- **WHEN** the skill is invoked with no arguments
- **THEN** it runs in interactive mode, classifying remote agent branches, presenting the plan, and asking for confirmation before deleting

#### Scenario: Confirmation skipped for automation

- **WHEN** the user passes `--yes`
- **THEN** the skill runs non-interactively, skipping the confirmation prompt and proceeding directly to deleting the merged branches

### Requirement: Enumerate Remote Agent Branches

The skill SHALL refresh remote tracking state (fetching and pruning origin) and discover the set of remote branches matching the `worktree-agent-*` prefix on origin.

#### Scenario: Branches found

- **WHEN** one or more remote branches match the `worktree-agent-*` prefix after fetching and pruning origin
- **THEN** the skill collects them as the candidate set to classify

#### Scenario: Discovery refreshes remote state

- **WHEN** the skill begins a run
- **THEN** it fetches and prunes origin before listing candidate branches so stale remote-tracking refs do not produce false candidates

### Requirement: Classify Each Branch by Most-Recent PR

For each enumerated branch the skill SHALL determine the state of its most-recent pull request and assign exactly one of the classifications MERGED, OPEN, CLOSED-not-merged, or NO-PR. Only MERGED branches SHALL be eligible for deletion.

#### Scenario: Branch with a merged PR

- **WHEN** a branch's most-recent PR has been merged
- **THEN** the skill classifies it MERGED and marks it for deletion

#### Scenario: Branch with an open PR

- **WHEN** a branch's most-recent PR is open
- **THEN** the skill classifies it OPEN and skips it as work in progress

#### Scenario: Branch with a closed-not-merged PR

- **WHEN** a branch's most-recent PR is closed but was never merged
- **THEN** the skill classifies it CLOSED-not-merged and skips it as abandoned work that may need recovery

#### Scenario: Branch with no PR

- **WHEN** no pull request is found for a branch
- **THEN** the skill classifies it NO-PR and skips it as unknown provenance

### Requirement: Stop When Nothing To Delete

The skill SHALL stop without deleting anything when no branches qualify, distinguishing the case where no agent branches exist at all from the case where branches exist but none are merged.

#### Scenario: No candidate branches at all

- **WHEN** the classification yields no remote `worktree-agent-*` branches
- **THEN** the skill reports that none were found and stops

#### Scenario: Candidates exist but none are merged

- **WHEN** there are candidate branches but none classify as MERGED
- **THEN** the skill reports a per-bucket count (zero to delete, plus the CLOSED, OPEN, and NO-PR skip counts) and stops without deleting

### Requirement: Present the Plan and Confirm

The skill SHALL present the full classification grouped by bucket (MERGED to delete; CLOSED, OPEN, and NO-PR skipped) so the user can see what will and will not be touched, and MUST obtain confirmation before deleting unless confirmation was waived with `--yes`.

#### Scenario: Plan displayed before action

- **WHEN** at least one branch is classified MERGED
- **THEN** the skill displays each bucket with its count and the branch names it contains, including the skipped buckets

#### Scenario: Interactive confirmation required

- **WHEN** running in interactive mode and at least one branch is marked for deletion
- **THEN** the skill asks the user to confirm the number of branches before performing any deletion
- **AND** if the user declines, the skill stops without deleting anything

#### Scenario: Confirmation waived

- **WHEN** running with `--yes` and at least one branch is marked for deletion
- **THEN** the skill proceeds to deletion without prompting

### Requirement: Delete Merged Branches Only

The skill SHALL delete only the branches classified MERGED, removing each from origin, and MUST leave every non-merged branch in place.

#### Scenario: Deleting eligible branches

- **WHEN** the user confirms deletion (or confirmation was waived)
- **THEN** the skill deletes the MERGED branches from origin
- **AND** it leaves all OPEN, CLOSED-not-merged, and NO-PR branches untouched

### Requirement: Per-Branch Error Reporting

During deletion the skill SHALL collect per-branch outcomes into deleted, skipped, and error groups, and SHALL surface any errors in the final report rather than discarding them.

#### Scenario: Some deletions fail

- **WHEN** one or more individual branch deletions report errors while others succeed
- **THEN** the skill records the failed branches in the errors group and still reports the branches that were deleted

#### Scenario: Classification or deletion step fails outright

- **WHEN** an underlying step exits with a failure status
- **THEN** the skill surfaces the error output and stops

### Requirement: Final Report

The skill SHALL emit a final report that lists the branches deleted, the branches skipped grouped by reason (CLOSED rejected work preserved, OPEN active PR, NO-PR inspect manually), and any errors. The errors section SHALL be omitted when there are none.

#### Scenario: Run summary with skips

- **WHEN** the run finishes after deleting at least one branch
- **THEN** the skill reports the deleted branches and the skipped branches grouped by their reason

#### Scenario: No errors occurred

- **WHEN** the run completes without any deletion errors
- **THEN** the final report omits the errors section

### Requirement: Local State Untouched

The skill SHALL operate only on remote branches on origin and MUST NOT modify any local checkout, worktree, or branch.

#### Scenario: Remote-only operation

- **WHEN** the skill deletes remote branches
- **THEN** it leaves local checkouts and worktrees unchanged
- **AND** local cleanup is left to the complementary clean-worktrees skill
