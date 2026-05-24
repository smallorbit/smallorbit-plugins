# squadkit-spawn-team

## Purpose

Materialize a coordinated crew of agents from a profile. The skill picks an unused phonetic team name, loads the crew roster, optionally cuts an epic feature branch, provisions per-builder worktrees, registers the team via `TeamCreate` under an orchestrator-is-lead model, spawns each non-lead member with role-appropriate permission and model settings, probes the lead's coordination tools, and confirms readiness via harness idle notifications before entering the dispatch loop. The skill is idempotent against `~/.claude/teams/<name>/config.json` and supports both execution crews (produce code via PRs) and discovery crews (produce GitHub issue comments).

## Requirements

### Requirement: Orchestrator-is-Lead Model
The system SHALL run the team-lead role inside the orchestrator session itself and SHALL NOT spawn a separate `team-lead` agent or reserve a `team-lead` slot via `TeamCreate`.

#### Scenario: Lead never spawned as separate agent
- **WHEN** the resolved roster is being spawned
- **THEN** no `Agent` call is made for `team-lead` and the orchestrator session itself fulfils that role

#### Scenario: Legacy team-lead roster entries dropped
- **WHEN** a crew profile lists a `team-lead` instance
- **THEN** the instance is silently stripped from the resolved roster before spawning

### Requirement: Main Repo Root and Base Branch Resolution
The system SHALL resolve the main repository root via `git rev-parse --git-common-dir` and read `baseBranch` from `<repo-root>/.squadkit/config.json`, defaulting to `develop` only when the file or key is missing, and SHALL NOT hardcode `develop` elsewhere.

#### Scenario: Worktree caller resolves to main root
- **WHEN** invoked from a linked worktree
- **THEN** `REPO_ROOT` resolves to the main repo root via the shared `.git` directory

#### Scenario: Missing config defaults to develop
- **WHEN** `.squadkit/config.json` is absent or has no `baseBranch` key
- **THEN** `BASE_BRANCH` resolves to `develop`

#### Scenario: Configured baseBranch wins
- **WHEN** `.squadkit/config.json` records a `baseBranch`
- **THEN** that value is used everywhere `${BASE_BRANCH}` is referenced

### Requirement: Flag Parsing and Narrative Tail
The system SHALL parse the documented flags, cap `--builders` at 5 with a warning, and SHALL run the narrative-tail parser before declaring an unknown-flag error.

#### Scenario: Unknown flag still parses narrative tail
- **WHEN** `$ARGUMENTS` contains a trailing narrative like `to tackle issues 1319-1337`
- **THEN** the narrative is parsed as `--issues <range>` before any unknown-flag error is raised

#### Scenario: Builders capped at 5
- **WHEN** `--builders` exceeds 5
- **THEN** the value is capped at 5 and a warning is surfaced

#### Scenario: Ambiguous tail prompts instead of erroring
- **WHEN** the narrative tail cannot be parsed
- **THEN** the operator is asked via `AskUserQuestion` whether to skip, supply a range, or cancel

### Requirement: Interactive Permission Mode Resolution
The system SHALL resolve `RESOLVED_MODE` from explicit `--mode auto|bypass|none` flags verbatim and SHALL prompt via `AskUserQuestion` when `--mode inherit` (the default) is in effect.

#### Scenario: Explicit mode flag skips prompt
- **WHEN** `--mode auto`, `--mode bypass`, or `--mode none` is passed
- **THEN** the prompt is skipped and `MODE_SOURCE` records `explicit flag`

#### Scenario: Inherit mode triggers prompt
- **WHEN** `--mode inherit` is in effect
- **THEN** an `AskUserQuestion` with `auto` / `bypass` / `none` options is presented and `MODE_SOURCE` records `user-selected via prompt`

#### Scenario: Resolved mode line printed
- **WHEN** mode resolution completes
- **THEN** a single `permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)` line is printed

### Requirement: Phonetic Team Name Resolution
The system SHALL derive `<repo>-<phonetic>` team names using the NATO phonetic alphabet, pick the first unused candidate, and stop when every letter is taken.

#### Scenario: Custom name accepted verbatim
- **WHEN** `--name <custom>` is provided
- **THEN** the value is sanitized to `[a-z0-9-]+` and used without phonetic auto-naming

#### Scenario: First free letter chosen
- **WHEN** no `--name` is provided
- **THEN** the first NATO letter for which `~/.claude/teams/<repo>-<letter>/config.json` does not exist is selected

#### Scenario: Exhausted alphabet stops
- **WHEN** every NATO letter is taken
- **THEN** the skill stops and asks the operator to recycle a stale team or supply `--name`, without inventing a 27th letter

### Requirement: UUID Orphan Pre-flight Sweep
The system SHALL detect UUID-named team directories under `~/.claude/teams/`, confirm they have no live members, and offer cleanup via `AskUserQuestion`.

#### Scenario: Orphans surfaced for cleanup
- **WHEN** one or more UUID-named directories exist with no live members
- **THEN** the operator is offered `Clean all`, `Skip`, or `Pick which to clean`

#### Scenario: Live UUID never deleted
- **WHEN** a UUID-named directory still has a live member
- **THEN** it is excluded from cleanup and a warning is surfaced instead

### Requirement: Idempotency Against Existing Team Config
The system SHALL detect an existing `~/.claude/teams/<name>/config.json`, surface the current roster, and offer `Reuse`, `Add missing`, or `Cancel`.

#### Scenario: Reuse exits without spawning
- **WHEN** the operator chooses `Reuse`
- **THEN** the existing roster is printed and no new agents are spawned

#### Scenario: Add missing spawns only the gap
- **WHEN** the operator chooses `Add missing`
- **THEN** only members named in the resolved roster but absent from the config are spawned

#### Scenario: No duplicate live members ever
- **WHEN** a re-run targets an existing config
- **THEN** no member already present and live is spawned a second time

### Requirement: Crew Profile Loading and Kind Validation
The system SHALL load `plugins/squadkit/crews/<profile>.yaml`, validate the schema, default missing `kind:` to `execution`, and reject any `kind:` value other than `execution` or `discovery`.

#### Scenario: Missing kind defaults to execution
- **WHEN** the profile YAML omits `kind:`
- **THEN** the profile is treated as `kind: execution`

#### Scenario: Invalid kind rejected
- **WHEN** the profile declares `kind:` with any value other than `execution` or `discovery`
- **THEN** the skill stops with a diagnostic naming the allowed values

#### Scenario: Roster expansion applies modifier flags
- **WHEN** `--with`, `--without`, or `--builders` are supplied
- **THEN** they extend, remove, or set the per-role count on top of the profile-resolved roster

### Requirement: Issue Scope Resolution
The system SHALL resolve `--issues <range>` (or the parsed narrative equivalent) via `swarmkit:gh-fetch-issues` and persist the filtered list as `RESOLVED_BACKLOG` for the first dispatch prompt.

#### Scenario: Range delegated to sub-skill
- **WHEN** `--issues` is provided
- **THEN** `swarmkit:gh-fetch-issues` is invoked and its filtered (open + non-on-hold + non-`status:in-progress`) records are stored as `RESOLVED_BACKLOG`

#### Scenario: Empty resolution prompts before spawn
- **WHEN** the range expands to zero issues after filtering
- **THEN** the operator is asked whether to proceed without a preset backlog or abort

#### Scenario: Absent flag leaves backlog empty
- **WHEN** `--issues` is not provided
- **THEN** `RESOLVED_BACKLOG` stays empty and the lead is dispatched without a preset backlog

### Requirement: Mission Brief Resolution
The system SHALL resolve `--brief <value>` to text — reading `@<path>` references against the repo root and treating non-`@` values verbatim — trim trailing whitespace, and reject empty content.

#### Scenario: File reference read against repo root
- **WHEN** `--brief @<path>` is provided
- **THEN** the file is read (relative paths resolved against the repo root) and an error halts the spawn if it is unreadable

#### Scenario: Inline brief used verbatim
- **WHEN** `--brief <inline-text>` is provided without an `@`
- **THEN** the text is used verbatim after trimming trailing whitespace

#### Scenario: Empty brief rejected
- **WHEN** the resolved brief is empty
- **THEN** the skill stops with a diagnostic instructing the operator to supply non-empty content

### Requirement: Discovery Crew Constraints
The system SHALL reject `--epic` for `kind: discovery` profiles, require `--brief`, skip worktree provisioning, skip `claude.flowkit.prBase` pinning, and SHALL set `WORK_BRANCH` to `BASE_BRANCH`.

#### Scenario: Discovery rejects --epic
- **WHEN** a `kind: discovery` profile is resolved and `--epic` was provided
- **THEN** the skill stops with a diagnostic explaining the incompatibility

#### Scenario: Discovery missing brief prompts
- **WHEN** `kind: discovery` and no `--brief` is supplied
- **THEN** the operator is prompted to supply one inline, via `@path`, or cancel

#### Scenario: Discovery skips worktree provisioning
- **WHEN** spawning a discovery crew
- **THEN** no per-builder worktrees are created and every member shares the main workspace

### Requirement: Epic Branch Cutting and Cross-Pin Guard
The system SHALL cut `feature/<slug>-<issue>` via `flowkit:cut-epic` when `--epic` is provided or chosen, SHALL refuse to proceed when an incompatible epic is already pinned, and SHALL default the prompt toward cutting an epic when the resolved roster will produce three or more child PRs.

#### Scenario: Existing pin matches reuses silently
- **WHEN** `claude.flowkit.prBase` is already pinned to `feature/<slug>-<issue>` matching the requested slug
- **THEN** the skill proceeds silently and `cut-epic` reuses the branch idempotently

#### Scenario: Conflicting pin blocks the spawn
- **WHEN** `claude.flowkit.prBase` is already pinned to a different `feature/...` branch
- **THEN** the skill exits with operator guidance to clear the pin or re-run with `--epic` matching the pinned slug

#### Scenario: Multi-builder defaults to cut-epic
- **WHEN** the resolved roster has more than one builder and no `--epic` was supplied
- **THEN** the prompt biases toward `Cut epic` and `Use ${BASE_BRANCH}` is accepted only after explicit confirmation that the work is a single PR

### Requirement: Stale Worktree Pre-flight
The system SHALL sweep `.claude/worktrees/` for paths not matching the resolved roster and SHALL invoke `swarmkit:clean-worktrees` to remove orphans before provisioning.

#### Scenario: Orphan triggers sub-skill
- **WHEN** at least one existing worktree directory does not correspond to a member in the resolved roster
- **THEN** `swarmkit:clean-worktrees` is invoked

#### Scenario: Operator-pinned orphans surface first
- **WHEN** the operator has opted to keep specific stale paths
- **THEN** the orphan list is surfaced via `AskUserQuestion` before the sub-skill is invoked

### Requirement: Per-Builder Worktree Provisioning
The system SHALL create one `.claude/worktrees/<member>/` worktree per builder using `git worktree add --detach` when the roster has more than one builder, and SHALL share the main workspace when there is exactly one builder.

#### Scenario: Multi-builder fans out with detach
- **WHEN** the roster has more than one builder
- **THEN** each builder gets `.claude/worktrees/<member>/` provisioned via `git worktree add --detach "${WORK_BRANCH}"`

#### Scenario: Singleton skips worktrees and seeding
- **WHEN** the roster has exactly one builder
- **THEN** no worktree is created and env-file seeding is skipped

#### Scenario: Stale worktree prompts before reuse
- **WHEN** a worktree directory exists but is on a branch other than `${WORK_BRANCH}` (and is not detached)
- **THEN** the operator is asked to `Sweep`, `Reuse`, or `Abort` before any reuse

### Requirement: Worktree Seeding for Ignored Files
The system SHALL seed each provisioned worktree with ignored env files — auto-detecting them by default, or copying exactly the list named in `.squadkit/config.json`'s `worktreeSeed` array when present — and SHALL warn (not error) on missing entries.

#### Scenario: Auto-detect copies discovered env files
- **WHEN** no `worktreeSeed` override is configured
- **THEN** ignored files matching the documented env pattern are copied from the main worktree into each per-builder worktree

#### Scenario: Explicit seed list wins over auto-detect
- **WHEN** `worktreeSeed` is set in `.squadkit/config.json`
- **THEN** exactly that list is copied (relative to the repo root) and auto-detection is skipped

#### Scenario: Missing seed entries warned, not failed
- **WHEN** a file listed in `worktreeSeed` is missing on disk
- **THEN** the spawn continues and the missing path is surfaced in the final summary

### Requirement: TeamCreate Without Agent Type
The system SHALL call `TeamCreate({team_name, description})` without an `agent_type` argument and SHALL halt with a diagnostic if any member is registered with an empty `tmuxPaneId` (phantom slot).

#### Scenario: agent_type never passed
- **WHEN** the team is registered
- **THEN** the `TeamCreate` call carries only `team_name` and `description`

#### Scenario: Phantom slot halts the spawn
- **WHEN** the post-register sanity check finds any member with empty `tmuxPaneId`
- **THEN** the skill halts and surfaces the phantom slot rather than proceeding with a polluted roster

### Requirement: Member Spawn with Layered Contracts
The system SHALL spawn each non-lead member with the role contract from `plugins/squadkit/agents/<role>.md` and SHALL append any project-local overlay at `.claude/agents/<role>.md` on top (project-local wins on conflict).

#### Scenario: Project-local overlay layered on top
- **WHEN** `.claude/agents/<role>.md` exists alongside `plugins/squadkit/agents/<role>.md`
- **THEN** the project-local content is appended after the bundled contract in the spawn prompt

#### Scenario: Required spawn parameters supplied
- **WHEN** any non-lead member is spawned
- **THEN** the spawn prompt carries `member_id`, `role`, `team_name`, `worktree_path`, `work_branch`, `base_branch`, and `squadkit_config_path`

### Requirement: Architect-Only Mission Brief Embedding
The system SHALL embed `MISSION_BRIEF` verbatim under a `## Mission brief` section in the architect spawn prompt only, prepending any fetched `## Epic context` block when `--epic` was supplied alongside `--brief`.

#### Scenario: Brief embedded verbatim in architect
- **WHEN** `MISSION_BRIEF` is non-empty and the architect member is being spawned
- **THEN** the brief is appended verbatim under `## Mission brief` without paraphrase or re-order

#### Scenario: Other roles never receive the brief at spawn
- **WHEN** any non-architect member is being spawned
- **THEN** `MISSION_BRIEF` is not embedded in their spawn prompt

#### Scenario: Epic context prepended to brief
- **WHEN** both `--epic` and `--brief` are provided and the epic body fetch succeeds
- **THEN** a `## Epic context` block precedes the `## Mission brief` block in the architect prompt

#### Scenario: Epic fetch failure falls back
- **WHEN** the `gh issue view` call for the epic body fails
- **THEN** the spawn proceeds with the brief alone and the failure is surfaced in the final summary

### Requirement: Spawn-time Mode and Model Selection
The system SHALL pass the `Agent({mode})` value derived from `RESOLVED_MODE` for every spawn and SHALL force `model: "opus"` on every spawned member when `RESOLVED_MODE=auto`, regardless of role frontmatter.

#### Scenario: Auto forces opus everywhere
- **WHEN** `RESOLVED_MODE=auto`
- **THEN** every spawned member — architect, builder, reviewer, tester, explorer, designer — is spawned with `model: "opus"` and `mode: "auto"`

#### Scenario: Bypass propagates without model override
- **WHEN** `RESOLVED_MODE=bypass`
- **THEN** every spawn carries `mode: "bypassPermissions"` and the role-default model is used

#### Scenario: None passes no override
- **WHEN** `RESOLVED_MODE=none`
- **THEN** no `mode` parameter is passed and the harness defaults apply

#### Scenario: Forced opus logged per spawn
- **WHEN** `RESOLVED_MODE=auto` and a role's frontmatter declared sonnet
- **THEN** a `RESOLVED_MODE=auto → forcing opus on <role>` line is logged per spawn

### Requirement: Tool-Registry Validation Probe
The system SHALL send a no-op `SendMessage` probe to the first spawned member after spawning but before waiting on idle notifications, SHALL halt the spawn on tool error or schema mismatch, and SHALL record success in the spawn summary.

#### Scenario: Successful probe recorded
- **WHEN** the probe `SendMessage` returns success and the harness summary digest matches the sent content
- **THEN** the probe result is recorded and the skill proceeds to idle-notification waiting

#### Scenario: Probe failure halts before readiness
- **WHEN** the probe returns a tool error, schema mismatch, or missing-tool error
- **THEN** the skill halts immediately, surfaces the gated tool and harness error text, and recommends a clean respawn

### Requirement: Idle-Notification Readiness
The system SHALL wait for one idle notification per spawned member with a 60-second per-member timeout and SHALL prompt the operator to retry, drop, or abort if any member fails to idle in time.

#### Scenario: Idle marks member ready
- **WHEN** a spawned member emits its first-turn idle notification
- **THEN** that member is marked ready

#### Scenario: Timeout prompts operator
- **WHEN** any member fails to idle within 60 seconds
- **THEN** the operator is asked to `Retry — wait another 60s`, `Drop — proceed without this member`, or `Abort — stop the spawn`

### Requirement: Squadkit Sibling Metadata File
The system SHALL write squadkit-specific coordination state to `~/.claude/teams/<name>/squadkit.json` with the documented schema and SHALL NOT overwrite the harness-managed `config.json` or duplicate `members[]`.

#### Scenario: Sibling file schema complete
- **WHEN** the sibling file is written
- **THEN** it contains `work_branch`, `base_branch`, `epic`, `repo_root`, `profile`, `kind`, `brief_provided`, `permissionMode`, and `spawned_at`

#### Scenario: permissionMode records resolved value
- **WHEN** `RESOLVED_MODE` is `auto`, `bypass`, or `none`
- **THEN** `permissionMode` is persisted as `auto`, `bypassPermissions`, or `none` respectively so mid-session spawns inherit it

#### Scenario: Harness config never overwritten
- **WHEN** the sibling file is written
- **THEN** the harness-managed `config.json` (with its `members[]`) is left untouched

#### Scenario: Sibling written only after every member idled
- **WHEN** any spawned member has not yet idled
- **THEN** the sibling file is not yet written

### Requirement: Final Dispatch Summary
The system SHALL print a summary covering team name, profile, work branch, roster, both metadata file paths, the `claude.flowkit.prBase` pin status (if any), worktree-seeding warnings, and the resolved permission mode line before entering the dispatch loop.

#### Scenario: Backlog table forwarded to dispatch
- **WHEN** `RESOLVED_BACKLOG` is non-empty
- **THEN** the first dispatch prompt to each builder includes a `## Backlog (resolved from --issues)` table

#### Scenario: Empty backlog dispatches default loop
- **WHEN** `RESOLVED_BACKLOG` is empty
- **THEN** the lead's dispatch loop begins without a preset scope and works against the team's own task list

#### Scenario: Permission mode line repeated
- **WHEN** the summary is emitted
- **THEN** the same `permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)` line printed at step 2.5 is repeated in the final summary

### Requirement: Orchestrator Playbook Branches
The system SHALL escalate to re-provision when the lead reports the same tool error twice with identical text on consecutive turns and SHALL treat idle as distinct from delivery by consulting `.squadkit/dispatch-log.jsonl` receipts before assuming a dispatch landed.

#### Scenario: Repeated identical tool error escalates
- **WHEN** the lead reports the same tool error twice with identical text on consecutive turns
- **THEN** the dispatch loop halts, the gated tool is surfaced, and a clean respawn is recommended without a third retry

#### Scenario: Tool-error receipt routes to escalation
- **WHEN** the most recent `(member, task)` receipt in `.squadkit/dispatch-log.jsonl` reports `outcome: tool_error`
- **THEN** the orchestrator treats the prior idle as a swallowed dispatch and falls through to the `lead-cannot-dispatch` branch
