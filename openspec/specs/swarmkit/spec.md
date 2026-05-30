# swarmkit

## Purpose

Resolve GitHub issues with parallel, isolated-worktree agents. Each agent creates a branch, implements the issue, opens a pull request, and stops — leaving all PRs open for human review and merge. Each PR also passes through an always-on review/fix pass before the run completes. Supports one-shot runs against specific issues, loop mode to continuously clear the board, and bottom-up stack merging via merge-stack.

## Requirements

### Requirement: Issue Fetching and Filtering
The system SHALL fetch open GitHub issues and exclude any issue labeled `on-hold` or `status:in-progress` from all ranking and dispatch operations.

#### Scenario: On-hold issues excluded
- **WHEN** an issue carries the `on-hold` label
- **THEN** it is not surfaced, ranked, or selected for agent dispatch

#### Scenario: In-progress issues excluded
- **WHEN** an issue carries the `status:in-progress` label
- **THEN** it is not surfaced, ranked, or selected for agent dispatch in subsequent cycles

### Requirement: Issue Ranking
The system SHALL rank open issues by priority label, implementation specificity, architectural impact, and testability before presenting candidates or selecting a batch.

#### Scenario: Priority labels respected
- **WHEN** issues carry `priority:high`, `priority:medium`, or `priority:low` labels
- **THEN** they are ranked in that order, with unlabeled issues evaluated from body content

#### Scenario: Specificity and impact favor architectural unblocking
- **WHEN** an issue's body calls out exact files, interfaces, or line numbers
- **THEN** it ranks above a same-priority issue with a vague description

### Requirement: One-Shot Mode
The system SHALL accept explicit issue numbers, gather their details in a single batch, analyze inter-issue dependencies, present a swarm plan before dispatching, and spawn one agent per issue (or grouped set) in parallel.

#### Scenario: Closed and on-hold issues skipped from requested set
- **WHEN** a requested issue is closed or labeled `on-hold`
- **THEN** it is excluded from `work_items` with the skip reason reported before dispatch

#### Scenario: Epic expansion
- **WHEN** a requested issue number is an epic with sub-issues wired via the native sub-issue API
- **THEN** the epic is expanded to its children; closed or on-hold children are excluded and reported

#### Scenario: Unwired epic skipped with guidance
- **WHEN** a requested issue is labeled `epic` but has no sub-issues attached via the native API
- **THEN** it is skipped with a message directing the operator to wire children before swarming

#### Scenario: Empty work set stops dispatch
- **WHEN** every requested issue (or every child of a requested epic) is filtered out
- **THEN** swarm announces the empty set and stops without spawning any agent

#### Scenario: Plan presented before dispatch
- **WHEN** work items are ready
- **THEN** a table showing agent assignments, branches, files affected, model, and merge order is presented before any agent spawns

### Requirement: Dependency Graph and Topological Dispatch
The system SHALL parse inter-issue dependencies from the native `blockedBy` API field (falling back to `Depends on #N` / `Blocked by #N` body text), build a directed acyclic graph, and dispatch agents in topological order.

#### Scenario: Independent issues spawn in parallel
- **WHEN** a set of issues has no dependency edges among them
- **THEN** all their agents spawn concurrently

#### Scenario: Dependent agent branches from upstream tip
- **WHEN** issue B depends on issue A within the same batch
- **THEN** the agent for B fetches and branches from `origin/worktree-agent-<A>` so A's output is already present in B's working tree without waiting for A's PR to merge

#### Scenario: Dependent agent PR targets upstream branch
- **WHEN** issue B depends on issue A
- **THEN** B's PR targets `worktree-agent-<A>` as its base, forming a stack

#### Scenario: Mid-swarm merge forbidden
- **WHEN** a downstream agent needs files from an upstream agent
- **THEN** the upstream PR is never merged early; the stacked-branch strategy provides the upstream output directly

### Requirement: Worktree Isolation
Every agent SHALL run in a dedicated git worktree under `.claude/worktrees/agent-<issue>`, use relative paths for all file operations, and abort if not inside a path containing `worktrees`.

#### Scenario: Worktree safety check aborts on wrong directory
- **WHEN** an agent's working directory does not contain the substring `worktrees`
- **THEN** the agent emits an error and exits without making changes

#### Scenario: Ancestry check aborts on stale base
- **WHEN** the agent's HEAD is not a descendant of `origin/<base>`
- **THEN** the agent emits an error with remediation instructions and exits

#### Scenario: Relative paths enforced
- **WHEN** agent prompts reference files in the repository
- **THEN** paths are relative to the worktree CWD; no absolute repo root paths appear in agent prompts

### Requirement: PR Creation Standards
Each agent SHALL create a branch named `worktree-agent-<issue>`, commit in conventional-commit format (no Claude mentions, no co-author lines), push the branch, and open a PR whose body includes a `Closes #<issue>` reference, a `## Summary` section, and a `## Test plan` section.

#### Scenario: Branch naming convention
- **WHEN** an agent is dispatched for issue N
- **THEN** its branch is named `worktree-agent-<N>`

#### Scenario: PR body standard sections
- **WHEN** a PR is opened
- **THEN** the body contains `## Summary`, `## Test plan`, and a `Closes #N` footer

#### Scenario: Conventional commit format
- **WHEN** an agent commits
- **THEN** the commit message follows `type(scope): description` with a subject line under 72 characters

#### Scenario: PR termination only after PR URL reported
- **WHEN** an agent reaches the end of its workflow
- **THEN** it does not stop until the PR exists and its URL has been reported

### Requirement: Issue Labeling
The system SHALL apply the `status:in-progress` label to each issue before its agent spawns, creating the label if it does not yet exist.

#### Scenario: Label created if absent
- **WHEN** the `status:in-progress` label does not exist in the repository
- **THEN** it is created before the first issue is labeled

#### Scenario: Label applied before dispatch
- **WHEN** an issue is selected for agent dispatch
- **THEN** `status:in-progress` is applied to the issue before the agent spawns

#### Scenario: Issue never closed by swarm
- **WHEN** an agent's PR is opened with `Closes #N`
- **THEN** the issue remains open until the PR merges; swarm never closes issues directly

### Requirement: Feature-Branch Mode
The system SHALL automatically cut a `feature/<slug>-<N>` branch via `flowkit:cut-epic` and pin `claude.flowkit.prBase` to it whenever a run will spawn two or more agents, routing all spawned PRs to the epic branch.

#### Scenario: Multi-issue one-shot cuts epic branch
- **WHEN** two or more issue numbers are passed
- **THEN** a feature branch is cut before any agent spawns; all PRs target that branch

#### Scenario: Loop mode cuts epic at first non-empty cycle
- **WHEN** loop mode starts with a non-empty board
- **THEN** the epic branch is cut at the start of the first cycle that selects at least one issue

#### Scenario: Single-issue one-shot stays flat
- **WHEN** exactly one issue number is passed
- **THEN** no epic branch is cut; the PR targets `$BASE` directly

#### Scenario: --no-epic suppresses the cut
- **WHEN** `--no-epic` flag is set
- **THEN** no epic branch is cut regardless of agent count; PRs target `$BASE` directly

#### Scenario: --base suppresses the cut
- **WHEN** `--base <branch>` is set
- **THEN** no epic branch is cut; all PRs target `<branch>` directly

#### Scenario: Empty board in loop mode skips cut
- **WHEN** loop mode finds no open issues at entry
- **THEN** the skill announces "Board is clear" and exits without cutting any branch

#### Scenario: Cross-pin guard prevents silent overwrite
- **WHEN** `claude.flowkit.prBase` is already set to a different `feature/` branch
- **THEN** swarm exits with an error message naming the existing pin and offering `--no-epic` or `--epic <existing-slug>` as escapes

#### Scenario: cut-epic is idempotent on resume
- **WHEN** the epic branch already exists on origin (e.g. resuming a loop run)
- **THEN** `cut-epic` reuses the existing branch and refreshes the pin

### Requirement: Loop Mode
The system SHALL continuously cycle through fetch → rank → batch → swarm until the board is clear, printing a checkpoint summary after each cycle and never pausing between cycles.

#### Scenario: Batch selection avoids file conflicts
- **WHEN** two open issues touch the same files
- **THEN** they are not selected in the same batch cycle

#### Scenario: Checkpoint printed after each cycle
- **WHEN** a swarm cycle completes
- **THEN** a checkpoint shows PRs opened, failed issues, blocked issues, and remaining count

#### Scenario: Failed issue blocks dependents in subsequent cycles
- **WHEN** an issue fails (agent crash, no PR produced)
- **THEN** all issues with file overlap or explicit references to the failed issue are marked blocked and skipped in current and future cycles

#### Scenario: Agent crash with no PR is unrecoverable
- **WHEN** an agent crashes without producing a PR
- **THEN** the loop halts immediately and reports the unrecoverable failure

#### Scenario: Base branch deletion is unrecoverable
- **WHEN** `$BASE` is deleted or corrupted externally during a loop run
- **THEN** the loop halts immediately

#### Scenario: prBase config cleaned up on teardown
- **WHEN** the loop completes or is torn down in non-epic mode
- **THEN** `claude.flowkit.prBase` is unset so subsequent PR-creation commands are not affected

#### Scenario: prBase kept on teardown in epic mode
- **WHEN** the loop completes in epic mode
- **THEN** `claude.flowkit.prBase` remains pinned to the epic branch and the operator is directed to run `/ship-epic`

### Requirement: Bottom-Up Stack Merge
The merge-stack skill SHALL retarget every non-root PR in a multi-PR chain to `$BASE` before merging anything, then merge each chain from root to leaf using a uniform squash-and-delete-branch strategy, rebasing each downstream PR onto `$BASE` after its predecessor merges.

#### Scenario: Only worktree-agent-* PRs are included
- **WHEN** merge-stack scans for open PRs
- **THEN** only PRs whose head branch starts with `worktree-agent-` are included

#### Scenario: Non-root PRs retargeted before first merge
- **WHEN** a multi-PR chain is present
- **THEN** every non-root PR's base is changed to `$BASE` before any merge runs, preventing GitHub's auto-close cascade

#### Scenario: Independent PRs merge in any order
- **WHEN** a PR's base is already `$BASE` and no other PR is stacked on it
- **THEN** it may merge in any order relative to other independent PRs

#### Scenario: Downstream PRs rebased after predecessor merges
- **WHEN** a non-leaf PR in a chain has been squash-merged into `$BASE`
- **THEN** every still-open downstream PR in that chain is rebased onto `$BASE` locally and force-pushed before the next merge, dropping the already-applied predecessor commits via patch-id matching

#### Scenario: Malformed closing-keyword footer warned before merge
- **WHEN** a PR body contains a space-separated multi-ref footer (e.g. `Closes #A #B`)
- **THEN** a warning is emitted before merge and the merge proceeds without blocking

#### Scenario: Conflict stops chain and blocks dependents
- **WHEN** a merge or rebase fails with a content conflict
- **THEN** the chain stops at that PR, all PRs above it in the chain are marked blocked, unrelated chains and independent PRs continue, and the user is directed to resolve and re-run

#### Scenario: No PR found stops cleanly
- **WHEN** no open PRs with `worktree-agent-` head branches exist
- **THEN** merge-stack reports "No open swarm PRs found" and stops

### Requirement: Automatic Review/Fix Pass
The swarm skill SHALL, always-on with no opt-out flag, dispatch one reviewer agent per PR as each swarm agent completes, apply a skip-on-clean rule to decide whether to spawn a fix-round worker, and produce a final summary of all verdict and worker outcomes.

#### Scenario: Reviewer dispatched as swarm agent completes
- **WHEN** a swarm agent reports its PR
- **THEN** the reviewer is dispatched immediately in the background without waiting for other swarm agents

#### Scenario: Skip-on-clean rule
- **WHEN** the reviewer verdict is `Approve` with no blockers, no concerns, and no `[recommended]` coverage gaps
- **THEN** no fix-round worker is spawned; the PR stands as-is

#### Scenario: Blocker or concern triggers fresh worker
- **WHEN** the reviewer surfaces any blocker, concern, or `[recommended]` coverage gap
- **THEN** a brand-new worker agent is spawned; the original builder agent is never re-engaged

#### Scenario: Worker branches from existing PR head
- **WHEN** a fix-round worker is spawned
- **THEN** it fetches and branches from the existing PR's head branch, not from `main`

#### Scenario: Nits and optional gaps never trigger a worker
- **WHEN** the reviewer's only findings are nits or `[optional]` coverage gaps
- **THEN** no fix-round worker is spawned

#### Scenario: Worker must not push a failing build
- **WHEN** a fix-round worker has applied changes
- **THEN** it runs the project's verify command and resolves any failures before pushing

#### Scenario: Single pass per PR
- **WHEN** a fix-round worker has completed and pushed
- **THEN** no second reviewer pass is triggered; users may invoke `/review <pr>` manually for a second opinion

#### Scenario: Reviewer output never posted as PR comment
- **WHEN** the reviewer produces findings
- **THEN** the findings are returned inline to the orchestrator only; no `gh pr comment` is posted by the reviewer

#### Scenario: Swarm agent failure skips review
- **WHEN** a swarm agent fails to produce a PR
- **THEN** no reviewer or worker is dispatched for that issue; the failure is noted in the final summary

### Requirement: Local Worktree Cleanup
The clean-worktrees skill SHALL remove all agent worktrees under `.claude/worktrees/` and delete all local branches with the `worktree-agent-*` prefix, halting if any worktree branch is still actively checked out.

#### Scenario: Stuck worktrees block cleanup
- **WHEN** a `worktree-agent-*` branch is still checked out by an active worktree
- **THEN** cleanup halts immediately and reports the stuck branches with manual remediation instructions

#### Scenario: Nothing to clean reported cleanly
- **WHEN** no agent worktrees or orphaned branches exist
- **THEN** the skill reports "Nothing to clean" and stops without error

#### Scenario: Caller branch restored after cleanup
- **WHEN** the caller's branch is among those removed
- **THEN** the result reports whether the caller branch was restored

### Requirement: Remote Branch Cleanup
The clean-remote-worktrees skill SHALL sweep orphaned remote `worktree-agent-*` branches, deleting only those whose most-recent PR is merged, and skipping open, closed-non-merged, and no-PR branches.

#### Scenario: Merged branches deleted
- **WHEN** a remote `worktree-agent-*` branch's most-recent PR is merged
- **THEN** it is selected for deletion

#### Scenario: Open PR branches skipped
- **WHEN** a remote `worktree-agent-*` branch's most-recent PR is still open
- **THEN** it is not deleted

#### Scenario: Closed-non-merged branches preserved
- **WHEN** a remote `worktree-agent-*` branch's most-recent PR was closed without merging
- **THEN** it is preserved (contains rejected work that exists nowhere else)

#### Scenario: No-PR branches surfaced for manual inspection
- **WHEN** a remote `worktree-agent-*` branch has no associated PR
- **THEN** it is reported for manual inspection and not deleted automatically

#### Scenario: Interactive mode confirms before deletion
- **WHEN** invoked without `--yes`
- **THEN** the plan is presented and user confirmation is required before any deletion

#### Scenario: --yes enables non-interactive deletion
- **WHEN** invoked with `--yes`
- **THEN** branches are deleted without prompting

#### Scenario: Idempotent on clean repo
- **WHEN** invoked when no remote `worktree-agent-*` branches exist
- **THEN** the skill reports nothing to delete and stops without error
