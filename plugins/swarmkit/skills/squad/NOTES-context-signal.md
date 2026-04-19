# Agent Teams context-usage signal — investigation

## Goal

Determine whether a `/squad` teammate can read its own context usage (tokens used, percentage of budget, or equivalent) from inside its own turn so the squad skill can implement preemptive handoff (epic #459) before the teammate hits its context limit.

## Investigation steps

All steps are reproducible against the official Claude Code documentation and the local repo on the date below. Fetched pages are the authoritative source; the findings below cite them directly.

### 1. Agent Teams API surface

Fetched <https://code.claude.com/docs/en/agent-teams> in full. The page describes the team model (lead, teammates, shared task list, mailbox) and every API primitive squad currently uses — `TeamCreate`, `Agent`/`Teammate` (spawn), `SendMessage`, `TeamDelete`, idle notifications — but defines no field, tool call, or event that exposes per-teammate token counts or context-usage percentages. The only teammate-health signals it documents are:

- `idle_notification` — fires when a teammate stops (no token payload).
- `isActive` in `~/.claude/teams/<team>/config.json` — boolean liveness flag, no usage data.
- The page's own **Limitations** section, which lists no context-usage tooling.

### 2. Task tool schemas (`TaskList`, `TaskGet`, `TaskCreate`, `TaskUpdate`)

Third-party docs that describe the Agent Teams tool surface in more detail than the official page — the [Agent Teams tool reference gist](https://gist.github.com/kieranklaassen/4f2aba89594a4aea4ad64d753984b2ea) and the [superpowers issue #429 tool list](https://github.com/obra/superpowers/issues/429) — enumerate the returned fields:

- `TaskGet` → `id, subject, description, status, owner, activeForm, blockedBy, blocks, createdAt, updatedAt`.
- `TaskList` → formatted rows with `id, status, subject, owner`.
- `TaskCreate` / `TaskUpdate` → no documented return schema beyond the task object.

**No token count, no context percentage, no remaining-budget field on any of them.** Tasks carry work metadata only; they are not a teammate-health surface.

### 3. Hooks

Fetched <https://code.claude.com/docs/en/hooks> and <https://code.claude.com/docs/en/agent-sdk/hooks>. Every hook input payload was inspected for token fields. Result:

- `TeammateIdle`, `TaskCreated`, `TaskCompleted` — fire around teammate lifecycle and task state, but their JSON payloads contain only `session_id, transcript_path, cwd, permission_mode, hook_event_name, teammate_name, team_name, idle_reason, task_id, task_subject, task_description`. No token/context field.
- `PreCompact` / `PostCompact` — fire around auto-compaction (which is a *proxy* for approaching the context limit), but they carry only `session_id, transcript_path, cwd, hook_event_name, trigger` ∈ {`"manual"`, `"auto"`}. No token value is attached.
- Every other hook (`PreToolUse`, `PostToolUse`, `SubagentStop`, `Stop`, `Notification`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`) — same story: session metadata plus event-specific data, no token-usage field.

There is no hook that fires at a context threshold (e.g. 75%, 90%). `PreCompact` fires at the *auto-compact* point, which the harness decides and does not pre-announce.

### 4. In-process signals available to the teammate itself

Surveyed every place the teammate could read its own state from inside its turn:

- **Env vars** (<https://code.claude.com/docs/en/env-vars> referenced from the commands page): `CLAUDE_CODE_*` vars exist for feature flags and limits, but none exposes the live context-usage counter.
- **Slash commands** — `/context`, `/cost`, `/stats`, `/status` all surface context or token data, but they are **user-facing UI commands**; the commands page at <https://code.claude.com/docs/en/commands> describes them as interactive visualizations, and the skills page at <https://code.claude.com/docs/en/skills> explicitly notes that only a small allowlist of built-ins is invocable via the `Skill` tool (`/init`, `/review`, `/security-review`) — `/compact`, `/context`, `/cost`, `/stats` are not on that list. A teammate cannot invoke them and parse their output from within its own agent loop.
- **Tool-result metadata** — no tool return documented in the Claude Code tools reference attaches a token-usage field to its result payload.
- **System-reminder injection** — Claude Code auto-compaction produces a summary system message when the limit is reached, but that is a one-shot post-hoc event, not a pre-threshold signal the teammate can poll.

### 5. Out-of-process signals that *do* exist (but aren't teammate-callable)

Documented for completeness:

- **Status line** (<https://code.claude.com/docs/en/statusline>) receives a JSON blob on stdin containing `context_window.used_percentage`, `context_window.remaining_percentage`, `context_window.total_input_tokens`, `context_window.total_output_tokens`, `context_window.context_window_size`, `context_window.current_usage.{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens}`, and `exceeds_200k_tokens`. This proves the harness *knows* per-session context usage — but only pushes it to an external display script, never to the model's own turn.
- **Agent SDK `query()` result message** (<https://code.claude.com/docs/en/agent-sdk/cost-tracking>) exposes `total_cost_usd`, `modelUsage`, and per-step `usage.{input_tokens,output_tokens,cache_*}` to the SDK *caller*, not to the agent inside its own loop. A teammate is a Claude Code session, not the SDK caller, so it cannot read its own `ResultMessage`.

### 6. Local repo search

`Grep` for `context.?usage|token.?count|token.?budget|tokens.?used|context.?budget|context.?window|context.?limit|contextPercent|tokenCount` across the repo returns exactly one hit — a narrative reference to "agent context limits" in the root `README.md`. No existing squad or swarmkit code reads a context-usage field. `Grep` for `TaskList|TaskGet|TaskCreate|TaskUpdate|Teammate|team_name|isActive|used_percentage` across the repo returns only `plugins/swarmkit/skills/squad/SKILL.md`. There is no hidden prior art in this codebase that contradicts the findings above.

## Findings

**No signal exists at time of writing (2026-04-19).**

Evidence:

- The official Agent Teams page (<https://code.claude.com/docs/en/agent-teams>) defines no per-teammate context-usage API.
- Every documented Agent Teams tool (`TaskList`, `TaskGet`, `TaskCreate`, `TaskUpdate`, `SendMessage`, `TeamCreate`, `TeamDelete`, `Teammate`) returns work-state or liveness data only.
- Every hook event (`TeammateIdle`, `TaskCreated`, `TaskCompleted`, `PreCompact`, `PostCompact`, plus all non-teams hooks) omits any token-usage field from its input payload.
- No bundled slash command that surfaces context data (`/context`, `/cost`, `/stats`) is callable from inside an agent turn — those UIs render to the user, not to a tool result the teammate can read.
- Harness-level signals that *do* carry `context_window.used_percentage` (statusline stdin, SDK `ResultMessage.usage`) are one-way pushes to external consumers (shell scripts, SDK callers), not to the teammate's own turn.

**Implication:** epic #459 cannot be built on a first-party, in-turn context-usage read. Any "teammate detects it is at 75% and warns the lead" mechanism needs a platform feature that does not exist today. Downstream squad tasks must either:

1. Wait for the Claude Code platform to expose a per-session token/context read to the agent itself (e.g. a new tool like `ContextGet`, a reserved env var populated each turn, or a hook fired at a configurable threshold), **or**
2. Fall back to a proxy heuristic. Candidates in descending order of signal quality:
   - **Task-count heuristic** — the teammate tracks how many tasks / issues it has self-claimed since spawn and pushes a `teammate_warning` after N (e.g. 3 for builders). Crude but requires zero platform support.
   - **Turn-count heuristic** — the teammate tracks its own assistant-turn count and warns above a threshold (each turn is a rough proxy for context consumed). Less crude than task count for the long-running reviewer, still zero-dependency.
   - **Wall-clock heuristic** — warn after M minutes of active work. Weakest proxy because slow tasks consume less context than fast tool-heavy tasks.
   - **`PreCompact` hook as a warning signal** — register a `PreCompact` hook in the squad spawn prompt and have it emit a `teammate_warning`; this fires only when auto-compact is about to run, so it is a *reactive* signal at ≈100% capacity, not the preemptive 75% trigger the epic specifies. Useful as a last-ditch backstop, not as the primary threshold check.

None of the above can meet the epic's current acceptance criterion 2 ("context usage crosses a hard-coded 75% threshold"). The criterion is grounded in a signal that does not exist.

## Implications for epic #459

| Child | State | Action |
|---|---|---|
| #454 — "teammate threshold check" | **Blocked as specified.** | Re-scope before starting. Either wait on a platform feature or rewrite the acceptance criterion around a heuristic (task count is the cleanest proxy for builders; turn count works for the reviewer). |
| #455 — "teammate-warning push to lead" | **Partly unblocked.** | The payload, successor-spawn flow, and naming scheme (`<role>-hN`) are independent of the signal — that work can proceed on top of whatever trigger #454 ends up using. Only the trigger source is blocked. |
| Epic #459 acceptance #1 ("`SKILL.md` documents how a teammate reads its own context-usage signal") | **Must be rewritten.** | Current criterion assumes an API read. The real deliverable is "documents the heuristic it uses and why no direct read exists." This note is the citable source. |
| Epic #459 acceptance #2 ("hard-coded 75% threshold") | **Must be rewritten.** | 75% of what is unmeasurable today. Replace with a heuristic threshold (e.g. "after 3 self-claimed tasks" for builders, "after 40 served audit requests" for the reviewer) or hold the whole epic until platform support lands. |
| Epic #459 acceptance #3–8 (payload shape, teardown auto-force-clear, `-hN` naming, queue-drain policy) | **Unblocked.** | Independent of the signal source. |

Recommended next step before unblocking #454 / #455: file a platform feature request upstream (Claude Code issue tracker) for a per-teammate context-usage read, and in parallel decide whether to ship the v1 of preemptive handoff on the task-count heuristic or wait. The task-count path is low-risk and testable today; the platform path is higher-quality but has no ETA.

## Date

2026-04-19
