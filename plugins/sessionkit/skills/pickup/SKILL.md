---
name: pickup
description: Load a handoff document and orient the agent to continue a previous session's work. Use at the start of a new session after /handoff was run.
triggers:
  - "/pickup"
  - "pick up where we left off"
  - "load handoff"
  - "resume from handoff"
  - "continue previous session"
allowed-tools: Bash, Read, TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Skill
---

# Pickup

Companion to `/handoff`. At the start of a new session, invoke `/pickup` to restore context written by the previous agent into `.sessionkit/HANDOFF.md`, so work can continue seamlessly.

## Process

### 1. Discover handoff file

Check for `.sessionkit/HANDOFF.md` in the current working directory:

```bash
cat .sessionkit/HANDOFF.md 2>/dev/null
```

If the file does not exist, fail gracefully: report

> No handoff file found at `.sessionkit/HANDOFF.md`. Either `/handoff` was not run in the previous session, or you're in a different working directory.

Then stop — do not proceed with the remaining steps.

### 2. Read and parse

Read the full content of `.sessionkit/HANDOFF.md`. Parse the standard sections: **Project**, **Date**, **Branch**, **Goal**, **Progress**, **Git State**, **Remaining Work**, **Context**. Unknown headings are passed through unmodified — section parsing is open-ended, so any future or legacy section names (including the legacy `## Team State` block emitted by sessionkit ≤ 1.5.0) are silently ignored.

### 3. Present orientation summary

Output a structured summary to orient the agent. Surface essentials, not the document verbatim:

- **Goal** — restate clearly in one or two sentences
- **Progress** — summarize what was done and what decisions were made
- **Git State** — branch, staged/unstaged files, recent commits
- **Remaining Work** — list in priority order
- **Context** — surface any important gotchas or notes the next agent must know

### 4. Hydrate task list

Parse the `## Task List` section from `.sessionkit/HANDOFF.md`:

1. Locate the fenced ` ```json ` block immediately following the `## Task List` heading.
2. If no `## Task List` section exists, or the JSON block is absent or unparseable, emit exactly one line in the orientation summary:
   > `No task list snapshot — skipping hydration`
   Then skip the remaining steps in this section and continue with step 5.

**Pass 1 — create tasks:**

For each task object in the array whose `status` is `pending` or `in_progress`:

- Call `TaskCreate` with `subject`, `description`, and `activeForm` from the JSON object.
  - `TaskCreate` always creates tasks as `pending`; do not attempt to force `in_progress` status.
- Record the mapping `oldId → newId` (old `id` comes from the JSON; new `id` is returned by `TaskCreate`).

Skip tasks whose `status` is `completed` — they are history and are already surfaced in the orientation summary.

**Pass 2 — restore blockedBy edges:**

After all `TaskCreate` calls complete, iterate the same set of created tasks. For each task that had a non-empty `blockedBy` array in the JSON:

- Remap each old ID in `blockedBy` to its new ID using the map built in Pass 1.
- Call `TaskUpdate` with `addBlockedBy` for the new task ID.

Do not wire `blocks` — the inverse relationship is implicit and wiring both directions would double-write the graph.

### 5. Restore git state (if needed)

Compare the handoff's branch against the current branch:

```bash
git branch --show-current
```

If they differ, suggest:

```bash
git checkout <branch-from-handoff>
```

Only suggest this when there's a mismatch. Do not switch branches automatically.

### 6. Confirm readiness

End by asking the user what to tackle first via the `AskUserQuestion` tool. Frame the question around the handoff's `Goal` and derive 2–4 concrete options from the `Remaining Work` list (highest-priority items first):

- **question**: `Context loaded. Ready to continue work on: <Goal>. What would you like to tackle first?`
- **header**: `Next action` (or similar short label)
- **options**: one option per top Remaining Work item, with a short description summarizing scope/effort

If `Remaining Work` has fewer than 2 actionable items, fall back to plain text:

> Context loaded. Ready to continue work on: `<Goal>`. What would you like to tackle first?

Do not pose this as a plain-text question when `AskUserQuestion` is viable — the structured prompt is the canonical end-of-pickup interaction.

## Constraints

- Never modify `.sessionkit/HANDOFF.md` — this skill is read-only
- Do not assume the handoff file always exists — always check first and fail gracefully
- Keep the orientation summary concise — surface the essentials, not everything verbatim
- Do not automatically re-execute any commands referenced in the handoff — the goal is to orient, not to act
