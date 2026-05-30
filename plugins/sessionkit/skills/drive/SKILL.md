---
name: drive
description: Execute an approved task chain autonomously from start to finish. Mark each task in_progress before starting and completed immediately after. Surface to the user only for blockers, executive decisions (scope changes, forking choices), or completion. Use after a plan has been approved — typically dispatched by `/sessionkit:roadmap`, but can be invoked standalone when a task list is already prepared.
triggers:
  - "/drive"
  - "drive the plan"
  - "drive the task list"
  - "execute the roadmap"
  - "you're driving"
  - "drive it"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TaskList, TaskGet, TaskCreate, TaskUpdate, AskUserQuestion, Skill, Agent
---

# Drive

## Process

### 1. Confirm there's a chain to drive

Call `TaskList`. If the result has no `pending` or `in_progress` tasks, stop with:

> Nothing to drive — the task list is empty or fully completed. Add tasks (or run `/sessionkit:roadmap`) before invoking `/drive`.

If there are tasks but they all have unresolved `blockedBy` edges pointing at non-existent IDs, report the broken state and stop. Do not silently start work on a corrupted graph.

### 2. State the driving contract (one preamble, then silence)

Before the first tool call of the chain, output exactly one short preamble so the user knows you've taken over:

> Driving from task #N. I'll work the chain top-down, mark tasks completed as I go, and only surface for blockers or executive decisions. Press Esc to interrupt at any time.

Do not narrate again until you finish, hit a blocker, or need a decision. The task list itself is the progress signal — every `TaskUpdate` is visible to the user without prose.

### 3. Drive loop

Repeat until the chain is empty:

1. **Pick the next task.** `TaskList` → take the lowest-ID task whose `status` is `pending` and whose `blockedBy` array is empty (or whose blockers are already `completed`). Ties broken by ID. If multiple `in_progress` tasks exist, finish them before picking a new one.
2. **Mark `in_progress`.** Call `TaskUpdate` with `status: in_progress` *before* doing any work for the task. One task in_progress at a time.
3. **Execute the task.** Read the task's `description` (use `TaskGet` if needed). Three execution shapes:
   - **Named skill** — description references a skill (e.g. "Run `/flowkit:merge-pr`", "Use `flowkit:ship`"): invoke it via the `Skill` tool. Pass arguments mentioned in the description verbatim.
   - **Explicit command** — description gives a shell command or sequence: run via `Bash`.
   - **Open-ended work** — description describes an outcome (e.g. "Self-review the diff and confirm X"): perform the work using whatever tools fit. Read, edit, search — whatever the description implies.
4. **Mark `completed`.** Immediately after the task's outcome is achieved, `TaskUpdate` with `status: completed`. Never batch — completing two tasks before updating either is a contract violation.
5. **Loop.** Go back to step 1.

### 4. Surface conditions (when to break the silence)

Surface to the user **only** when one of these is true. Otherwise, keep driving silently.

| Condition | What it means | How to surface |
|-----------|---------------|----------------|
| **Blocker** | A tool failed in a way you cannot recover from (auth missing, network down, dependency missing, hook rejected without an obvious fix, irreversible-state needed). | Plain text: state what failed, what you tried, what's needed. Leave the task `in_progress`. Stop. |
| **Executive decision** | A genuine fork in approach not covered by the task description; a scope change emerges; two valid paths with materially different consequences. | `AskUserQuestion` with 2–4 options and your recommendation labeled `(Recommended)`. Resume on answer. |
| **Risky/destructive action** | The next step would delete data, rewrite shared history, force-push, mass-modify external systems, or send messages on the user's behalf. | Plain text confirmation prompt — describe the action and ask permission. Do not bury it inside an `AskUserQuestion`. |
| **Completion** | All tasks completed. | Final report (see step 5). |

What does **not** count as a surface condition:
- Routine tool failures with obvious remediation (try again, fix the typo, adjust the path).
- Each task starting/finishing — the task list updates carry that signal.
- Cosmetic choices with no downstream impact (commit message wording, branch naming when no convention is given).
- "Just to confirm" moments. If you're confident, proceed. If you're not, that's an executive decision — surface.

### 5. Final report

When the chain is fully completed (no pending or in_progress tasks remain), output a tight report:

```
Driven to completion: <N> tasks, <T> minutes.

Highlights:
- <one-line summary per task that produced an artifact: PR opened, tag created, file modified, etc.>

Outstanding:
- <anything the user should know about — created follow-ups, deferred work, surfaced findings>
```

Keep it short. The task list itself records the steps; the report adds anything the list can't carry (URLs, IDs, things created).

## Constraints

- **One task `in_progress` at a time.** Mark `in_progress` before starting, `completed` immediately after, never batch.
- **No narration.** No "starting task #5", "moving on to #6", "now I'll do X". The task list is the progress feed.
- **No silent destructive actions.** Even when driving, ask before deleting data, force-pushing, or modifying shared/production state.
- **No silent scope expansion.** If a task turns out to need a sub-task that wasn't in the plan, add it via `TaskCreate` (with appropriate `blockedBy`) so it's visible — don't smuggle work into an unrelated task.
- **Blocker etiquette.** Leave the failing task in `in_progress` so the next session/agent can resume it. Don't mark it `completed` if you didn't complete it.
- **Read tasks fresh.** Use `TaskGet` between steps if a description might have been edited — don't cache stale state.
- **Never modify task subjects/descriptions to make them easier.** If a task is wrong, surface it as an executive decision.
