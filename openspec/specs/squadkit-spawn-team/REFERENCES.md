# squadkit-spawn-team — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `<repo-root>/`.
Line numbers verified on 2026-05-24.

---

## Requirement: Orchestrator-is-Lead Model

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:17` — "**Orchestrator-is-lead model.** ... The skill never spawns a separate `squadkit:team-lead` agent and never reserves a `team-lead` slot via `TeamCreate({agent_type: ...})`".
- `plugins/squadkit/skills/spawn-team/SKILL.md:189` — roster build step 5: "**Strip every `team-lead` instance from the resolved roster** — the orchestrator IS the lead."
- `plugins/squadkit/skills/spawn-team/SKILL.md:594` — constraint "Never spawn a separate `squadkit:team-lead` agent — the orchestrator IS the lead."

### Scenario: Lead never spawned as separate agent
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:17` — same line as above.
**Interpolated; no direct test.**

### Scenario: Legacy team-lead roster entries dropped
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:189` — "If a profile lists `team-lead` (legacy), drop it silently; do not re-add it."
**Interpolated; no direct test.**

---

## Requirement: Main Repo Root and Base Branch Resolution

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:51-72` — Step 1 "Resolve the repo root and base branch" walks through `git rev-parse --git-common-dir`, the `jq -r '.baseBranch // "develop"'` defensive read, and the "Never hardcode `develop` elsewhere" rule.
- `plugins/squadkit/skills/spawn-team/SKILL.md:587` — constraint "Never hardcode `develop` — always read `${BASE_BRANCH}` from `.squadkit/config.json`".

### Scenario: Worktree caller resolves to main root
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:53-61` — `COMMON=$(git rev-parse --git-common-dir ...) ... REPO_ROOT=$(cd "$(dirname "$COMMON")" && pwd)`.
**Interpolated; no direct test.**

### Scenario: Missing config defaults to develop
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:69` — `jq -r '.baseBranch // "develop"' "$SQUAD_CONFIG" 2>/dev/null || echo "develop"`.
**Interpolated; no direct test.**

### Scenario: Configured baseBranch wins
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:72` — "Never hardcode `develop` elsewhere in the runbook — every reference uses `${BASE_BRANCH}` resolved here."
**Interpolated; no direct test.**

---

## Requirement: Flag Parsing and Narrative Tail

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:23-33` — flag table including the `--builders` cap-at-5 rule and the `--mode inherit` default.
- `plugins/squadkit/skills/spawn-team/SKILL.md:35-47` — "Narrative-tail parsing" subsection enumerating the accepted shapes and the prompt-on-failure rule.
- `plugins/squadkit/skills/spawn-team/SKILL.md:74-81` — Step 2 "Parse arguments" with the narrative-tail-before-error rule.

### Scenario: Unknown flag still parses narrative tail
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:76` — "Treat unknown flags as an error and stop, but always run the **narrative-tail parser** described in the Input section before declaring an unknown-flag error".
**Interpolated; no direct test.**

### Scenario: Builders capped at 5
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:79` — "Coerce `--builders` to an integer; reject non-numeric input. If the value exceeds 5, cap it at 5 and warn."
Also `plugins/squadkit/skills/spawn-team/SKILL.md:589` constraint: "Never create more than 5 builders, even if the user asks."
**Interpolated; no direct test.**

### Scenario: Ambiguous tail prompts instead of erroring
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:43-47` — "If parsing fails (ambiguous tail, mixed flags and narrative), do **not** error — prompt via `AskUserQuestion`" with `Skip — no scope` / `Provide range` / `Cancel` options.
**Interpolated; no direct test.**

---

## Requirement: Interactive Permission Mode Resolution

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:83-108` — Step 2.5 "Resolve the effective permission mode" with the explicit-flag vs. inherit-prompt branching and the printed-line spec.
- `plugins/squadkit/skills/spawn-team/SKILL.md:602` — constraint reinforcing the prompt vs. skip rule per `--mode` value.

### Scenario: Explicit mode flag skips prompt
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:89` — "If `--mode auto`, `--mode bypass`, or `--mode none` was passed explicitly, use it verbatim and skip the prompt. Set `MODE_SOURCE=explicit flag`."
**Interpolated; no direct test.**

### Scenario: Inherit mode triggers prompt
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:90-98` — "If `--mode inherit` (the default ...), call `AskUserQuestion` with the following three options. Set `MODE_SOURCE=user-selected via prompt`".
**Interpolated; no direct test.**

### Scenario: Resolved mode line printed
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:100-104` — "After resolution, print one line: `permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)`".
**Interpolated; no direct test.**

---

## Requirement: Phonetic Team Name Resolution

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:110-128` — Step 3 "Resolve the team name" with the NATO array, the first-free iteration, and the alphabet-exhausted stop.
- `plugins/squadkit/skills/spawn-team/SKILL.md:590` — constraint "Never invent a phonetic letter beyond `zulu` — stop and ask."

### Scenario: Custom name accepted verbatim
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:112` — "If `--name <custom>` is provided, use it verbatim (after sanitizing to `[a-z0-9-]+`)."
**Interpolated; no direct test.**

### Scenario: First free letter chosen
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:119-125` — bash loop iterating `PHONETIC` and breaking on first non-existing `~/.claude/teams/<repo>-<letter>/config.json`.
**Interpolated; no direct test.**

### Scenario: Exhausted alphabet stops
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:128` — "If every phonetic letter is taken, stop and report".
**Interpolated; no direct test.**

---

## Requirement: UUID Orphan Pre-flight Sweep

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:130-147` — Step 3.1 "UUID-orphan pre-flight sweep" with the `find` regex, the no-live-members confirmation, and the `Clean all` / `Skip` / `Pick which to clean` prompt.

### Scenario: Orphans surfaced for cleanup
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:141-145` — "If at least one orphan is detectable, prompt the user via `AskUserQuestion`" with the three option labels.
**Interpolated; no direct test.**

### Scenario: Live UUID never deleted
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:147` — "Never delete a UUID dir that still has a live member — surface a warning instead."
**Interpolated; no direct test.**

---

## Requirement: Idempotency Against Existing Team Config

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:149-157` — Step 4 "Idempotency check" with the three operator options and the no-duplicates rule.
- `plugins/squadkit/skills/spawn-team/SKILL.md:588` — constraint "Never spawn duplicate live members against an existing `~/.claude/teams/<name>/config.json`."

### Scenario: Reuse exits without spawning
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:153` — "`Reuse` — print the existing roster and exit (no new agents)."
**Interpolated; no direct test.**

### Scenario: Add missing spawns only the gap
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:154` — "`Add missing` — only spawn members named in the resolved roster that aren't already in the config."
**Interpolated; no direct test.**

### Scenario: No duplicate live members ever
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:157` — "Re-running the skill against an existing config must never duplicate a live member."
**Interpolated; no direct test.**

---

## Requirement: Crew Profile Loading and Kind Validation

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:159-189` — Step 5 "Load the crew profile" with the YAML schema, kind validation rules, the execution-default fallback, and the roster expansion sub-steps.
- `plugins/squadkit/skills/spawn-team/SKILL.md:599` — constraint reinforcing the kind enum and execution default.

### Scenario: Missing kind defaults to execution
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:176` — "If `kind:` is omitted, default to `execution` — this preserves backward compatibility with crew profiles authored before the field existed".
**Interpolated; no direct test.**

### Scenario: Invalid kind rejected
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:172-175` — "If `kind:` is present but not one of `execution` or `discovery`, reject the profile with: `Crew profile <profile> declares kind: <value>, which is not a recognized crew kind. Allowed values: execution, discovery.`"
**Interpolated; no direct test.**

### Scenario: Roster expansion applies modifier flags
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:183-189` — numbered list 1-5: expand counts, apply `--builders`, append `--with`, remove `--without`, strip `team-lead`.
**Interpolated; no direct test.**

---

## Requirement: Issue Scope Resolution

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:191-203` — Step 5.5 "Resolve the issue scope (optional)" with the sub-skill invocation, empty-result prompt, and absent-flag fallback.

### Scenario: Range delegated to sub-skill
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:193-199` — `Skill({skill: "swarmkit:gh-fetch-issues", args: "<resolved range>"})` and "Persist this list as `RESOLVED_BACKLOG`".
**Interpolated; no direct test.**

### Scenario: Empty resolution prompts before spawn
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:201` — "If the range expands to zero issues after filtering, warn the user and ask via `AskUserQuestion` whether to proceed with no preset backlog or abort."
**Interpolated; no direct test.**

### Scenario: Absent flag leaves backlog empty
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:203` — "If `--issues` was not provided, skip this step — `RESOLVED_BACKLOG` stays empty".
**Interpolated; no direct test.**

---

## Requirement: Mission Brief Resolution

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:213-219` — Step 5.6 "Brief resolution" subsection with the `@<path>` vs. inline branches, trimming, and empty-content rejection.

### Scenario: File reference read against repo root
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:215` — "If `<value>` starts with `@`, treat the rest as a path. Read the file (relative to the repo root if not absolute). If the file is missing or unreadable, stop with: `--brief @<path> could not be read: <error>`."
**Interpolated; no direct test.**

### Scenario: Inline brief used verbatim
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:216` — "Otherwise treat `<value>` verbatim as the brief text."
**Interpolated; no direct test.**

### Scenario: Empty brief rejected
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:217` — "Trim trailing whitespace. If the resulting text is empty, stop with: `--brief value resolved to empty content. Provide a non-empty brief.`"
**Interpolated; no direct test.**

---

## Requirement: Discovery Crew Constraints

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:205-227` — Step 5.6 discovery-mode `--epic` rejection and brief-requires prompt.
- `plugins/squadkit/skills/spawn-team/SKILL.md:247-249` — Step 6 "Skip entirely when `kind: discovery`" guard for epic feature-branch ownership.
- `plugins/squadkit/skills/spawn-team/SKILL.md:312` — Step 7 "Skip entirely when `kind: discovery`" guard for worktree provisioning.
- `plugins/squadkit/skills/spawn-team/SKILL.md:598` — constraint summarizing the four discovery-crew prohibitions and the brief requirement.

### Scenario: Discovery rejects --epic
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:209-211` — "If the resolved profile has `kind: discovery` and `--epic` was provided ..., stop with: `Crew profile <profile> is kind: discovery ...`".
**Interpolated; no direct test.**

### Scenario: Discovery missing brief prompts
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:221-225` — "**Discovery requires a brief.** If `kind: discovery` and `MISSION_BRIEF` is empty ..., prompt via `AskUserQuestion`" with `Provide brief — paste inline` / `Provide brief — supply @path` / `Cancel`.
**Interpolated; no direct test.**

### Scenario: Discovery skips worktree provisioning
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:312` — "**Skip entirely when `kind: discovery`.** Discovery crews are read-only and produce no per-builder branches; every member shares the main workspace."
**Interpolated; no direct test.**

---

## Requirement: Epic Branch Cutting and Cross-Pin Guard

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:251-290` — Step 6 pre-flight rule, prompt options, cross-pin guard bash, and `flowkit:cut-epic` invocation.

### Scenario: Existing pin matches reuses silently
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:278` — "When the existing pin matches the resolved feature branch, proceed silently — cut-epic is idempotent and will reuse the branch."
**Interpolated; no direct test.**

### Scenario: Conflicting pin blocks the spawn
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:270-275` — cross-pin guard bash: `if [[ -n "$EXISTING_PIN" && "$EXISTING_PIN" =~ ^feature/ && "$EXISTING_PIN" != "feature/${slug}-${issue}" ]]; then ... exit 1; fi`.
**Interpolated; no direct test.**

### Scenario: Multi-builder defaults to cut-epic
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:251` — "Any spawn that will produce three or more child PRs MUST run on a feature branch ... When the resolved roster includes more than one builder, or the user's intent names three or more deliverables, default the prompt toward cutting an epic and only accept `Use ${BASE_BRANCH}` after the user confirms".
**Interpolated; no direct test.**

---

## Requirement: Stale Worktree Pre-flight

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:292-308` — Step 6.5 "Stale-worktree pre-flight" with the `find` listing, sub-skill invocation, and operator-pinned prompt.

### Scenario: Orphan triggers sub-skill
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:300-304` — `Skill({skill: "swarmkit:clean-worktrees"})` invocation block.
**Interpolated; no direct test.**

### Scenario: Operator-pinned orphans surface first
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:308` — "If the user has explicitly opted to keep specific stale paths, surface them via `AskUserQuestion` before invoking the sub-skill."
**Interpolated; no direct test.**

---

## Requirement: Per-Builder Worktree Provisioning

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:310-350` — Step 7 "Worktree provisioning" with singleton vs. multi-builder branch, the `--detach` bash, the stale-branch prompt, and the rationale for `--detach`.
- `plugins/squadkit/skills/spawn-team/SKILL.md:595-596` — constraints "Never silently reuse a stale `.claude/worktrees/<member>/` ..." and "Worktrees live under `.claude/worktrees/<member>/` ... Always created with `--detach`".

### Scenario: Multi-builder fans out with detach
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:340` — `git worktree add --detach "${WT_PATH}" "${WORK_BRANCH}"`.
**Interpolated; no direct test.**

### Scenario: Singleton skips worktrees and seeding
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:316` — "**Singleton (1 builder)**: every member shares the current workspace. Skip worktree creation. Skip the env-file seeding subsection".
**Interpolated; no direct test.**

### Scenario: Stale worktree prompts before reuse
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:324-338` — `if [ -d "${WT_PATH}" ]` block with the `Sweep` / `Reuse` / `Abort` operator question.
**Interpolated; no direct test.**

---

## Requirement: Worktree Seeding for Ignored Files

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:352-379` — "Worktree seeding (env files and other ignored files)" subsection with auto-detect bash, explicit `worktreeSeed` override, and missing-file warning.

### Scenario: Auto-detect copies discovered env files
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:358-367` — `git ls-files --others --ignored --exclude-standard | grep -E '^(\.env...' | while read -r envfile; do cp ... done`.
**Interpolated; no direct test.**

### Scenario: Explicit seed list wins over auto-detect
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:369-375` — "**Explicit override** — if `.squadkit/config.json` defines a `worktreeSeed: [...]` list, copy exactly that list (relative to the repo root) and skip the auto-detection."
**Interpolated; no direct test.**

### Scenario: Missing seed entries warned, not failed
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:377` — "If a listed file is missing, warn but do not error — surface every missing path in the final summary so the user can remediate."
**Interpolated; no direct test.**

---

## Requirement: TeamCreate Without Agent Type

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:381-402` — Step 7.5 "Register the team via TeamCreate" with the no-`agent_type` rule, rationale, and post-register phantom-slot sanity check.
- `plugins/squadkit/skills/spawn-team/SKILL.md:593` — constraint "Never pass `agent_type` to `TeamCreate` — it reserves a phantom slot."
- `plugins/squadkit/skills/spawn-team/SKILL.md:609` — harness constraint "`TeamCreate({agent_type: ...})` reserves a phantom slot."

### Scenario: agent_type never passed
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:386` — `TeamCreate({team_name: "${TEAM_NAME}", description: "<one-line description from the crew profile>"})`.
**Interpolated; no direct test.**

### Scenario: Phantom slot halts the spawn
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:396-402` — sanity-check `jq` command and "If output is non-empty, halt the skill and surface the phantom — never proceed with a polluted roster."
**Interpolated; no direct test.**

---

## Requirement: Member Spawn with Layered Contracts

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:404-417` — Step 8 spawn-prompt construction, project-local overlay append, and required spawn parameters.

### Scenario: Project-local overlay layered on top
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:406` — "If a project-local overlay exists at `.claude/agents/<role>.md`, **append** it to the contract (project-local layered on top of the plugin contract — project-local wins on conflict)."
**Interpolated; no direct test.**

### Scenario: Required spawn parameters supplied
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:408-416` — bulleted list of the seven required spawn parameters.
**Interpolated; no direct test.**

---

## Requirement: Architect-Only Mission Brief Embedding

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:418-428` — Step 8 "Architect-only mission brief" subsection and "Other roles stay mission-agnostic" reinforcement.
- `plugins/squadkit/skills/spawn-team/SKILL.md:231-243` — Step 5.6 "Epic context prepending (execution only)" composing the `## Epic context` block atop `## Mission brief`.
- `plugins/squadkit/skills/spawn-team/SKILL.md:600` — constraint reinforcing architect-only embedding.

### Scenario: Brief embedded verbatim in architect
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:418-426` — "When spawning the `architect` member and `MISSION_BRIEF` is non-empty, append the brief verbatim ..." with the `## Mission brief` block and the "do not paraphrase, summarize, or re-order" directive.
**Interpolated; no direct test.**

### Scenario: Other roles never receive the brief at spawn
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:428` — "Do **not** embed `MISSION_BRIEF` in the spawn prompts for explorer, designer, builder, reviewer, tester, or any other non-architect role."
**Interpolated; no direct test.**

### Scenario: Epic context prepended to brief
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:233-241` — `## Epic context` / `## Mission brief` template; "If `--epic <slug>` was provided alongside `--brief`, fetch the GitHub issue body for `<issue>` ... and prepend it to `MISSION_BRIEF`".
**Interpolated; no direct test.**

### Scenario: Epic fetch failure falls back
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:243` — "If the epic fetch fails (network, missing issue, auth), warn but do not abort — fall back to the brief alone, and surface the failure in the final summary."
**Interpolated; no direct test.**

---

## Requirement: Spawn-time Mode and Model Selection

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:430-450` — Step 8 "Spawn-time mode + model selection" subsection with the mode→model table, rationale, and per-spawn forced-opus log line.
- `plugins/squadkit/skills/spawn-team/SKILL.md:601` — constraint reinforcing the all-members-opus invariant under auto.

### Scenario: Auto forces opus everywhere
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:436` — table row "`auto` | `\"auto\"` | **all members forced to `opus`** — architect, builder, reviewer, tester, explorer, designer — regardless of role frontmatter".
**Interpolated; no direct test.**

### Scenario: Bypass propagates without model override
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:437` — table row "`bypass` | `\"bypassPermissions\"` | none — role frontmatter default".
**Interpolated; no direct test.**

### Scenario: None passes no override
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:438` — table row "`none` | not passed — harness defaults apply | none".
**Interpolated; no direct test.**

### Scenario: Forced opus logged per spawn
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:442-446` — "When `RESOLVED_MODE=auto` and a role's frontmatter declared sonnet, log per spawn: `RESOLVED_MODE=auto → forcing opus on <role>`".
**Interpolated; no direct test.**

---

## Requirement: Tool-Registry Validation Probe

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:452-481` — Step 8.5 "Tool-registry validation probe" with success assertions, failure handling, and cross-reference to the `lead-cannot-dispatch` playbook entry.

### Scenario: Successful probe recorded
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:471` — "**On success:** record the probe result (timestamp + delivered digest) in the spawn summary, then proceed to step 9."
**Interpolated; no direct test.**

### Scenario: Probe failure halts before readiness
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:473-479` — "**On failure (tool error, schema mismatch, or missing tool):** halt squad creation immediately. Do not proceed to step 9. Surface to the user: ... Which tool was gated ... The exact error text ... A recommendation: re-provision the orchestrator".
**Interpolated; no direct test.**

---

## Requirement: Idle-Notification Readiness

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:483-501` — Step 9 "Readiness confirmation — idle-notification-as-ack" with the N-notifications wait, 60-second per-member timeout, and operator prompt on miss.

### Scenario: Idle marks member ready
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:492` — "As each notification arrives, mark that member ready."
**Interpolated; no direct test.**

### Scenario: Timeout prompts operator
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:493-497` — "If any member fails to idle within 60s, surface the missing role and ask the user via `AskUserQuestion` ... Options: `Retry — wait another 60s`, `Drop — proceed without this member`, `Abort — stop the spawn`."
**Interpolated; no direct test.**

---

## Requirement: Squadkit Sibling Metadata File

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:503-535` — Step 10 "Persist squadkit metadata (sibling file, not the harness config)" with the schema, `permissionMode` mapping, and the never-overwrite rule.
- `plugins/squadkit/skills/spawn-team/SKILL.md:591-592` — constraints "Never write the squadkit sibling file before every member has idled" and "Never overwrite the harness-managed `config.json` — append squadkit metadata to the sibling `squadkit.json` instead."

### Scenario: Sibling file schema complete
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:515-527` — JSON schema block with all nine fields.
**Interpolated; no direct test.**

### Scenario: permissionMode records resolved value
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:531` — "Map `RESOLVED_MODE` to the persisted value as follows: `auto` → `\"auto\"`, `bypass` → `\"bypassPermissions\"`, `none` → `\"none\"`."
**Interpolated; no direct test.**

### Scenario: Harness config never overwritten
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:505` — "**Do not overwrite it** — overwriting clobbers the members[] array and breaks peer addressability."
**Interpolated; no direct test.**

### Scenario: Sibling written only after every member idled
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:591` — constraint "Never write the squadkit sibling file before every member has idled."
**Interpolated; no direct test.**

---

## Requirement: Final Dispatch Summary

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:537-561` — Step 11 "Hand off to the team-lead (the orchestrator itself)" with the bulleted summary fields and the `## Backlog (resolved from --issues)` table template.

### Scenario: Backlog table forwarded to dispatch
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:549-559` — "The first dispatch prompt sent to each builder MUST include the resolved backlog (if `RESOLVED_BACKLOG` is non-empty) as a structured section" with the table template.
**Interpolated; no direct test.**

### Scenario: Empty backlog dispatches default loop
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:561` — "If `RESOLVED_BACKLOG` is empty, dispatch the lead's loop with no preset scope — it works against the team's own task list."
**Interpolated; no direct test.**

### Scenario: Permission mode line repeated
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:547` — bullet "`permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)` — the same line printed at step 2.5, repeated here so the human has a record in the final summary."
**Interpolated; no direct test.**

---

## Requirement: Orchestrator Playbook Branches

**Sources**
- `plugins/squadkit/skills/spawn-team/SKILL.md:563-583` — "Orchestrator playbook" section enumerating `lead-cannot-dispatch` and the delivery-receipt channel.

### Scenario: Repeated identical tool error escalates
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:567-569` — "If after handing off to the dispatch loop the lead reports the same tool error twice with identical text on consecutive turns, **escalate to re-provision — do not retry a third time**."
**Interpolated; no direct test.**

### Scenario: Tool-error receipt routes to escalation
**Source:** `plugins/squadkit/skills/spawn-team/SKILL.md:571-583` — "Delivery-receipt channel" subsection: "The orchestrator reads the latest `(member, task)` line before assuming a dispatch landed; on `tool_error`, fall through to the `lead-cannot-dispatch` branch above."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **No automated tests for this skill.** Behavior is documented entirely in `SKILL.md` prose. Every scenario above is interpolated from the SKILL.md directives.
2. **`auto ⇒ opus everywhere` is load-bearing.** Spec line for `Auto forces opus everywhere` mirrors SKILL.md line 436 exactly; the "all members" enumeration (architect, builder, reviewer, tester, explorer, designer) is reproduced literally because the previous "non-builder only" carve-out was explicitly dropped (lines 440 and 601). Changing the enumeration changes operator-observable behavior.
3. **60-second per-member idle timeout is a single source of truth.** Defined only on line 491 of SKILL.md and reproduced verbatim in the spec; no other source defines it.
4. **Discovery vs. execution gating is fan-out.** A single `kind: discovery` value gates four spec requirements (epic rejection, brief requirement, worktree skip, prBase skip). The composite "Discovery Crew Constraints" requirement captures all four together; the individual SKILL.md sources are spread across lines 30, 32, 181, 209-225, 247-249, 312, 598.
5. **The harness-constraint section** (SKILL.md lines 605-616) intentionally documents *workaround rationale* rather than additional behavior. The spec does not capture it as a separate requirement because each workaround is already reflected in the requirement it motivates (e.g. `--detach` is in "Per-Builder Worktree Provisioning"; the `TeamCreate({agent_type})` rule is in "TeamCreate Without Agent Type"; sonnet-prompts-in-auto motivates the `auto ⇒ opus` rule). Reviewers should sanity-check that any new harness constraint added there has a matching spec requirement.
6. **Known-issue zombie-subprocess sweep** (SKILL.md lines 635-647) is operator guidance for the manual workaround to `TeamDelete`'s upstream bug (#924), not a spawn-team behavior — it is intentionally not captured as a spec requirement.
