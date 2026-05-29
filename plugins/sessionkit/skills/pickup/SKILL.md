---
name: pickup
description: Load a handoff document and orient the agent to continue a previous session's work. Use at the start of a new session after /handoff was run.
triggers:
  - "/pickup"
  - "pick up where we left off"
  - "load handoff"
  - "resume from handoff"
  - "continue previous session"
allowed-tools: Bash, Read, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Skill, Agent
---

# Pickup

## Execution model

Pickup runs its reading, parsing, and orientation synthesis on Haiku regardless of the session's active model — Haiku is materially faster and the work is mechanical. The work is split:

- **Haiku sub-agent** — reads and parses `.sessionkit/HANDOFF.md`, produces the orientation summary, extracts the task snapshot, and derives the readiness question/options. It returns this as structured output; it does not touch session state or the user.
- **Outer tier (this skill, any model)** — performs only the operations that must land in *this* session or reach the user: the absent-file guard, `TaskCreate`/`TaskUpdate` hydration, the branch-mismatch suggestion, and the final `AskUserQuestion`.

The outer tier MUST pass full self-contained instructions to the sub-agent inline. It MUST NOT tell the sub-agent to "run the pickup skill" or reference this skill by name — that would re-trigger the skill and recurse.

## Process

### 1. Absent-file guard (outer tier)

Check for `.sessionkit/HANDOFF.md` in the current working directory:

```bash
test -f .sessionkit/HANDOFF.md && echo "found" || echo "missing"
```

If missing, report and stop — do not dispatch the sub-agent:

> No handoff file found at `.sessionkit/HANDOFF.md`. Either `/handoff` was not run in the previous session, or you're in a different working directory.

### 2. Dispatch the Haiku sub-agent

Invoke the `Agent` tool with:

- `subagent_type`: `"general-purpose"`
- `model`: `"haiku"`
- `prompt`: the verbatim operating instructions below. Do not reference this skill by name anywhere in the prompt.

> You are parsing a session handoff document to orient the next agent. Read `.sessionkit/HANDOFF.md`, then return the structured result described below. Do not call any task tools and do not ask the user anything — you have no session-state or user access. Your returned text IS the result.
>
> **A. Read and parse.** Read the full file. Parse the standard sections: **Project**, **Date**, **Branch**, **Goal**, **Progress**, **Git State**, **Remaining Work**, **Context**. Ignore unknown headings silently — parsing is open-ended, so legacy or future section names must not cause errors.
>
> **B. Task snapshot.** Locate the fenced `json` block immediately following the `## Task List` heading. If the section is missing or the block is absent/unparseable, set `tasksToCreate` to `[]` and `taskListMissing` to `true`. Otherwise, for each object whose `status` is `pending` or `in_progress`, include it in `tasksToCreate` with its `id` (as `oldId`), `subject`, `description`, `activeForm`, `status`, and `blockedBy`. Skip `completed` tasks.
>
> **C. Current branch.** Run `git branch --show-current` and record it as `currentBranch`. Record the handoff's branch as `handoffBranch`.
>
> **D. Readiness.** Derive 2–4 concrete next-action options from `Remaining Work` (highest priority first). Each option is `{label, description}`. If fewer than 2 actionable items exist, set `options` to `[]`.
>
> **E. Return** exactly one markdown orientation summary followed by one fenced `json` block — nothing else. The orientation summary covers Goal (restated in 1–2 sentences), Progress (what was done/decided), Git State (branch, staged/unstaged, recent commits), Remaining Work (priority order), and Context (gotchas/notes) — concise, not the document verbatim. The json block:
> ```json
> {
>   "goal": "<one-line goal>",
>   "taskListMissing": false,
>   "tasksToCreate": [
>     { "oldId": "<id>", "subject": "<s>", "description": "<d>", "activeForm": "<a>", "status": "<pending|in_progress>", "blockedBy": ["<oldId>"] }
>   ],
>   "currentBranch": "<branch>",
>   "handoffBranch": "<branch>",
>   "options": [ { "label": "<short>", "description": "<scope/effort>" } ]
> }
> ```

**Fallback**: if the Agent call fails or returns no parseable json block, read and parse `.sessionkit/HANDOFF.md` yourself inline using the same rules, then continue.

### 3. Present orientation (outer tier)

Print the sub-agent's orientation summary to the user.

### 4. Hydrate task list (outer tier)

Using the sub-agent's `tasksToCreate`:

- If `taskListMissing` is true (or `tasksToCreate` is empty), emit one line: `No task list snapshot — skipping hydration` and skip to step 5.
- **Pass 1 — create tasks.** For each entry, call `TaskCreate` with its `subject`, `description`, and `activeForm`. `TaskCreate` always creates as `pending` — do not force `in_progress`. Record `oldId → newId`.
- **Pass 2 — restore edges.** For each entry with a non-empty `blockedBy`, remap each old ID to its new ID and call `TaskUpdate` with `addBlockedBy`. Do not wire `blocks` — the inverse is implicit and would double-write the graph.

These calls run in the outer tier so the tasks land in *this* session's list.

### 5. Restore git state (outer tier)

If `currentBranch` differs from `handoffBranch`, suggest (do not run):

```bash
git checkout <handoffBranch>
```

Only suggest on mismatch. Never switch branches automatically.

### 6. Confirm readiness (outer tier)

If the sub-agent returned 2 or more `options`, ask via `AskUserQuestion`:

- **question**: `Context loaded. Ready to continue work on: <goal>. What would you like to tackle first?`
- **header**: `Next action`
- **options**: the sub-agent's `options` (label + description)

If fewer than 2 options, fall back to plain text:

> Context loaded. Ready to continue work on: `<goal>`. What would you like to tackle first?

## Constraints

- Never modify `.sessionkit/HANDOFF.md` — this skill is read-only with respect to the handoff document
- Do not automatically re-execute any commands referenced in the handoff — the goal is to orient, not to act
