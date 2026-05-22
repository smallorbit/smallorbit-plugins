# Sweep

## Purpose
Sweep removes accumulated cruft from a codebase in two coordinated phases — dead code (unused exports, imports, variables, unreachable branches) and stale artifacts (outdated docs, build leftovers, duplicate content, merged remote branches) — with interactive confirmation before any changes are applied. It is the hygiene counterpart to Polish, focused on safe removal with user control over every action.

## Requirements

### Requirement: Scope intake
Sweep SHALL accept an optional scope argument that restricts processing. A path or glob restricts both phases to that subtree. A category hint (dead-code-only, cruft-only, git-only) restricts to the matching phase. An absent scope runs both phases across the full repository.

#### Scenario: Full sweep (no scope)
- **WHEN** no scope argument is provided
- **THEN** both Phase 1 (dead code) and Phase 2 (cruft) run across the full repository

#### Scenario: Path or glob scope
- **WHEN** a path or glob is provided
- **THEN** both phases are restricted to that subtree

#### Scenario: Category hint scope
- **WHEN** a category hint such as `dead-code-only`, `cruft-only`, or `git-only` is provided
- **THEN** only the phase matching that hint runs

### Requirement: Dead code detection
Sweep SHALL detect the primary language(s) and available static analysis tools before scanning. It SHALL scan for unused exports, unused imports, dead variables, unreachable branches, and commented-out code blocks using the most capable tool available for each language. Findings SHALL be skipped for node_modules/, dist/, build/, .next/, generated files (*.generated.ts, *.d.ts), and test files.

#### Scenario: TypeScript project scanned
- **WHEN** a TypeScript project is detected
- **THEN** Sweep uses ts-prune (if available) for unused exports and tsc --noEmit for unused locals and unreachable branches

#### Scenario: Test files excluded
- **WHEN** a dead-code candidate is located in a test file
- **THEN** it is excluded from findings

### Requirement: Cruft detection
Sweep SHALL check for stale documentation (WIP or tracking files referencing completed work; PRDs for shipped features), build artifacts and dead directories (empty directories, committed build output not in .gitignore), documentation gaps (README or user-facing docs not reflecting current features), duplicate content (root-level files duplicating content already in docs/), and git hygiene (local merged branches, stale worktrees, orphaned remote-tracking branches, and remote branches tied to merged PRs).

#### Scenario: Remote branch classification
- **WHEN** Phase 2 runs
- **THEN** Sweep fetches the remote, lists all non-default non-parked remote branches, and classifies each by its PR state: MERGED, CLOSED, OPEN, or NO PR

#### Scenario: Only merged-PR branches proposed for deletion
- **WHEN** remote branches are classified
- **THEN** only MERGED branches are proposed for deletion; CLOSED, OPEN, and NO PR branches are preserved

### Requirement: Remote branch deletion safety
When deleting remote branches, Sweep SHALL use the disambiguated refspec form `git push origin :refs/heads/<branch>` rather than `git push origin --delete <branch>`. Multiple deletions SHALL be batched into a single push call. This prevents failures when a same-named tag exists.

#### Scenario: Single remote branch deletion
- **WHEN** one remote branch is confirmed for deletion
- **THEN** deletion uses `git push origin :refs/heads/<branch>`

#### Scenario: Multiple remote branch deletions
- **WHEN** more than one remote branch is confirmed for deletion
- **THEN** all are batched into a single `git push origin :refs/heads/<a> :refs/heads/<b>` call

### Requirement: Interactive confirmation
Before executing any changes, Sweep SHALL compile all findings from both phases into a combined Remove / Update / Keep summary and confirm each proposed action via AskUserQuestion. Questions SHALL be batched with at most 4 questions per call. Closely related items SHALL be grouped into a single question. Sweep SHALL wait for all answers before executing any change.

#### Scenario: Confirmation collected before execution
- **WHEN** findings are compiled
- **THEN** Sweep presents all proposed actions and waits for complete user confirmation before modifying any file or running any command

#### Scenario: Question batching
- **WHEN** more than 4 independent confirmations are needed
- **THEN** questions are spread across multiple AskUserQuestion calls with at most 4 questions each

### Requirement: Cleanup execution and commit
After confirmation, Sweep SHALL apply all approved removals and edits, verify that modified source files still parse (tsc --noEmit or language equivalent), re-run the project's verify command if one is available, commit with the message `chore: sweep codebase`, and open a PR targeting the project's base branch (develop if it exists on the remote, otherwise the repository default).

#### Scenario: Post-removal parse check
- **WHEN** dead code is removed from a source file
- **THEN** Sweep verifies the file still parses before committing

#### Scenario: Commit and PR opened
- **WHEN** all approved changes are applied and verification passes
- **THEN** Sweep commits with `chore: sweep codebase` and opens a PR targeting develop, or the repository default if develop does not exist
