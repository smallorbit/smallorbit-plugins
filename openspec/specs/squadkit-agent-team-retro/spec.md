# squadkit-agent-team-retro

## Purpose

Evolve squad role contracts from real-session learnings. The skill polls each currently-spawned team member with three fixed questions, synthesizes responses into severity-grouped action items, applies operator-approved edits to role contracts (project-local override preferred), optionally hands unapplied findings off to a catalog flow as GitHub issues, then cleans up per-member worktrees before retiring the team registry. The retro is session-scoped: it operates only on members spawned in the active team config, never on idle or historical rosters.

## Requirements

### Requirement: Active Team Discovery
The system SHALL discover the active team by reading `~/.claude/teams/<name>/config.json`, prefer the team whose `squadkit.json` sidecar records a `repo_root` equal to the orchestrator's main repo root, and prompt the operator to disambiguate when multiple candidates remain.

#### Scenario: Single team config
- **WHEN** exactly one `~/.claude/teams/*/config.json` is present
- **THEN** that team is selected without prompting

#### Scenario: Repo-root match disambiguates
- **WHEN** multiple team configs exist and one sibling `squadkit.json` records `repo_root` equal to the orchestrator's main repo root
- **THEN** that team is selected without prompting

#### Scenario: Ambiguous teams prompt operator
- **WHEN** repo-root matching cannot pick a single candidate
- **THEN** the candidates are surfaced via `AskUserQuestion` and the operator picks one

#### Scenario: No team config exits cleanly
- **WHEN** no team config is present (or only the orchestrator is recorded with no spawned members)
- **THEN** the skill emits a no-op message directing the operator to spawn a team first and exits without error

### Requirement: Spawned Member Filter
The system SHALL poll only members with a live `sessionId` recorded in `members[]` and SHALL exclude any member whose `sessionId` is null, empty, or terminated.

#### Scenario: Idle members excluded
- **WHEN** a `members[]` entry has no live `sessionId`
- **THEN** the member is excluded from the poll

#### Scenario: Empty filtered roster exits cleanly
- **WHEN** the filtered roster is empty after the live-session filter
- **THEN** the skill emits the same solo-session no-op message and exits without error

### Requirement: Three Fixed Questions
The system SHALL send each polled member the same three questions, verbatim and in the documented order, with each answer capped at 200 words.

#### Scenario: Question order preserved
- **WHEN** the poll fires
- **THEN** members receive (1) what worked well, (2) friction or blockers, (3) the single most useful role-contract change, in that order

#### Scenario: Over-limit answer compressed
- **WHEN** any answer exceeds 200 words
- **THEN** a single follow-up `SendMessage` asks the member to compress that answer, and the compressed version is used instead of silent truncation

### Requirement: Parallel Polling
The system SHALL fire all member `SendMessage` polls in a single batch and collect replies before aggregating.

#### Scenario: Single batch dispatch
- **WHEN** polls begin
- **THEN** every member receives the prompt in a single batch rather than sequentially

### Requirement: SendMessage Ack Discipline
The system SHALL treat each member's `SendMessage` reply (not an idle notification) as the completion signal for Phase 2 and SHALL re-ping members that go idle without a `SendMessage` payload before falling back to operator confirmation.

#### Scenario: Idle without reply triggers single re-ping
- **WHEN** a member emits an idle notification without a `SendMessage` payload within 60 seconds of the initial poll
- **THEN** exactly one re-ping is sent with the documented framing, and the skill waits again for a `SendMessage` reply

#### Scenario: Persistent non-responder waived via operator
- **WHEN** a member still has not replied after the re-ping
- **THEN** Phase 3 begins only after the operator explicitly waives the non-responder via `AskUserQuestion`

### Requirement: Severity Buckets
The system SHALL group action items into `high`, `medium`, and `low` buckets, with `high` reserved for items raised by two or more members or items that block a core protocol.

#### Scenario: Cross-member item promoted to high
- **WHEN** two or more members raise the same item
- **THEN** the item is classified `high`

#### Scenario: Protocol-blocking item promoted to high
- **WHEN** an item blocks a core protocol (handoff, spawn, review gate)
- **THEN** the item is classified `high` even if raised by a single member

### Requirement: Action Item Schema
The system SHALL record each action item with `id`, `severity`, `targetRole`, `summary`, and `rationale` fields, where `targetRole` is one of the named role contracts or `cross-cutting`.

#### Scenario: Item shape complete
- **WHEN** the aggregation produces an action item
- **THEN** all five fields are populated before approval

### Requirement: Per-Bucket Approval
The system SHALL surface action items via one `AskUserQuestion` per non-empty severity bucket, each multi-select, so the operator can cherry-pick within each tier.

#### Scenario: Empty bucket skipped
- **WHEN** a severity bucket contains no items
- **THEN** its question is not asked

#### Scenario: Unselected items fall through to catalog candidate set
- **WHEN** an item is presented but not approved
- **THEN** it is recorded as a Phase 6 catalog handoff candidate

### Requirement: Project-Local Override Resolution
The system SHALL prefer `.claude/agents/<targetRole>.md` over `plugins/squadkit/agents/<targetRole>.md` when applying edits.

#### Scenario: Project-local file edited directly
- **WHEN** `.claude/agents/<targetRole>.md` exists
- **THEN** the edit is applied to it directly without prompting

#### Scenario: Bundled-only requires consent
- **WHEN** only the bundled contract exists
- **THEN** the operator is asked whether to edit the bundle in place or copy it to a project-local override first, with the copy option recommended by default

#### Scenario: Neither file present is logged and skipped
- **WHEN** neither the project-local nor the bundled contract exists for a target role
- **THEN** the item is skipped and a warning is recorded in the final summary

#### Scenario: Cross-cutting items routed by operator
- **WHEN** an action item targets `cross-cutting`
- **THEN** the operator is asked which role(s) should receive the edit, or whether to defer the item to the catalog handoff

### Requirement: Minimal Surgical Edits
The system SHALL apply each approved edit as a minimal change to only the affected clause, never as a full rewrite.

#### Scenario: Edit scope bounded
- **WHEN** an approved edit is applied
- **THEN** only the clause being added, refined, or removed is touched

### Requirement: Opt-In Catalog Handoff
The system SHALL ask the operator whether unapplied findings should be filed as GitHub issues and SHALL invoke `speckit:catalog` only when the operator opts in.

#### Scenario: Yes hands off to catalog
- **WHEN** the operator opts in
- **THEN** the unapplied action items (id, severity, targetRole, summary, rationale) are passed to `speckit:catalog`

#### Scenario: No proceeds to teardown
- **WHEN** the operator declines
- **THEN** the skill proceeds directly to teardown without filing issues

### Requirement: Worktree Cleanup Before Team Delete
The system SHALL collect every per-member worktree path recorded in the team's `config.json` and `squadkit.json`, run `git worktree remove --force` on each, log cleaned and skipped paths, and only then invoke `TeamDelete`.

#### Scenario: Both metadata files consulted
- **WHEN** worktree paths are collected
- **THEN** entries from both `config.json` and `squadkit.json` are unioned and de-duplicated before removal

#### Scenario: Orchestrator cwd preserved
- **WHEN** the orchestrator's own `cwd` appears among collected paths
- **THEN** it is excluded so `git worktree remove` is never run against the caller's working directory

#### Scenario: Missing path logged as skipped
- **WHEN** a recorded worktree path does not exist on disk
- **THEN** it is logged as skipped with a reason and the cleanup continues without error

#### Scenario: TeamDelete runs after cleanup
- **WHEN** all collected paths have been processed
- **THEN** `TeamDelete` is invoked to retire the registry, after the metadata files have been read

### Requirement: Final Report
The system SHALL emit a final report including team name and roster size polled, action items applied per role and severity, action items skipped with reasons, whether the catalog handoff ran and how many issues were filed, and the worktree cleanup log.

#### Scenario: Report content complete
- **WHEN** the skill exits successfully
- **THEN** all five report elements are present in the output
