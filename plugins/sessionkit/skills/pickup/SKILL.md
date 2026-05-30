---
name: pickup
description: Load a handoff document and orient the agent to continue a previous session's work. Use at the start of a new session after /handoff was run.
triggers:
  - "/pickup"
  - "pick up where we left off"
  - "load handoff"
  - "resume from handoff"
  - "continue previous session"
allowed-tools: Bash, Read, TaskCreate, TaskUpdate, TaskList, AskUserQuestion
---

# Pickup

## Process

### 1. Absent-file guard

```bash
test -f .sessionkit/HANDOFF.md && echo "found" || echo "missing"
```

If missing, report and stop — do not continue:

> No handoff file found at `.sessionkit/HANDOFF.md`. Either `/handoff` was not run in the previous session, or you're in a different working directory.

### 2. Read and parse

`Read` `.sessionkit/HANDOFF.md` inline. Parse these sections: **Goal**, **Progress**, **Remaining Work**, **Context**, and the fenced `json` block under **Task List**. Ignore any unknown or legacy headings silently — parsing is open-ended.

### 3. Extract task snapshot

Locate the fenced `json` block immediately following the `## Task List` heading. For each object whose `status` is `pending` or `in_progress`, collect:
- `oldId` (the task's `id` from the snapshot)
- `subject`, `description`, `activeForm`, `status`, `blockedBy`

Skip objects with `status: completed`. If the block is absent, empty, or unparseable, set `tasksToCreate` to `[]` and note it.

### 4. Present orientation

Print a concise orientation summary — bullets, not a verbatim copy of the document:

- **Goal** — restated in 1–2 sentences
- **Progress** — what was done and decided
- **Remaining Work** — priority order
- **Context** — gotchas and notes

Do NOT add a section for git state — the handoff document does not contain one.

### 5. Hydrate task list

If `tasksToCreate` is empty, emit one line: `No task list snapshot — skipping hydration` and move to step 6.

**Pass 1 — create tasks.** For each entry, call `TaskCreate` with its `subject`, `description`, and `activeForm`. `TaskCreate` always creates as `pending` — do not force `in_progress`. Record `oldId → newId`.

**Pass 2 — restore edges.** For each entry with a non-empty `blockedBy`, remap each old ID to its new ID and call `TaskUpdate` with `addBlockedBy`. Do NOT wire `blocks` — the inverse is implicit.

### 6. Confirm readiness

Get the current branch:

```bash
git branch --show-current
```

If the current branch differs from the `**Branch**` value in the handoff header (if present), suggest — do not run:

```bash
git checkout <branch-from-handoff>
```

Then ask the user what to tackle first. Derive 2–4 concrete next-action options from the top items in **Remaining Work** (highest-priority first). Each option should have a short label and a brief scope/effort note.

If 2 or more options exist, use `AskUserQuestion`:
- **question**: `Context loaded. Ready to continue work on: <goal>. What would you like to tackle first?`
- **header**: `Next action`
- **options**: the derived options

If fewer than 2 options, use plain text:

> Context loaded. Ready to continue work on: `<goal>`. What would you like to tackle first?

## Constraints

- Never modify `.sessionkit/HANDOFF.md` — this skill is read-only with respect to the handoff document
- Do not automatically re-execute any commands referenced in the handoff — the goal is to orient, not to act
