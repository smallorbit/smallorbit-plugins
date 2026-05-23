# Drive — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Pre-flight chain validation

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:27-32` — Step 1 checks `TaskList` for no pending/in_progress tasks and stops with a message
- `plugins/sessionkit/skills/drive/SKILL.md:33` — Step 1 checks for broken `blockedBy` edges pointing at non-existent IDs

**Notes**
- The broken-graph check (all tasks blocked by non-existent IDs) is explicitly called out as a stop condition

### Scenario: Task list is empty
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:27-29` — "If the result has no `pending` or `in_progress` tasks, stop with: > Nothing to drive…"
Verified by presence in the guard clause. **Interpolated; no direct test.**

### Scenario: Broken dependency graph
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:31-33` — "If there are tasks but they all have unresolved `blockedBy` edges pointing at non-existent IDs, report the broken state and stop."
**Interpolated; no direct test.**

---

## Requirement: Single driving preamble

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:35-39` — Step 2 defines a verbatim preamble and states "Do not narrate again until you finish"

### Scenario: Driving starts
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:37-38` — verbatim preamble text with starting task ID and silence contract.
**Interpolated; no direct test.**

---

## Requirement: Task-state discipline

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:51` — "Mark `completed`. Immediately after the task's outcome is achieved… Never batch."
- `plugins/sessionkit/skills/drive/SKILL.md:89` — Constraints: "One task `in_progress` at a time."
- `plugins/sessionkit/skills/drive/SKILL.md:89` — "Mark `in_progress` before starting, `completed` immediately after, never batch."

### Scenario: Task lifecycle
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:47-52` — Steps 2 (mark in_progress before work) and 4 (mark completed immediately after).
**Interpolated; no direct test.**

### Scenario: Multiple in_progress tasks
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:45` — "If multiple `in_progress` tasks exist, finish them before picking a new one."
**Interpolated; no direct test.**

---

## Requirement: Task selection order

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:45` — "take the lowest-ID task whose `status` is `pending` and whose `blockedBy` array is empty (or whose blockers are already `completed`). Ties broken by ID."

### Scenario: Next unblocked task
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:45` — lowest-ID pending task with empty or completed `blockedBy`.
**Interpolated; no direct test.**

---

## Requirement: Task execution dispatch

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:47-51` — Step 3 defines three execution shapes: named skill, explicit command, open-ended work

### Scenario: Named skill task
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:48` — "Named skill — description references a skill (e.g. 'Run `/flowkit:merge-pr`'): invoke it via the `Skill` tool."
**Interpolated; no direct test.**

### Scenario: Shell command task
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:49` — "Explicit command — description gives a shell command or sequence: run via `Bash`."
**Interpolated; no direct test.**

### Scenario: Outcome-based task
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:50` — "Open-ended work — description describes an outcome… perform the work using whatever tools fit."
**Interpolated; no direct test.**

---

## Requirement: Controlled surface conditions

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:56-63` — Step 4 table defines four and only four surface conditions
- `plugins/sessionkit/skills/drive/SKILL.md:65-69` — "What does not count as a surface condition" list

### Scenario: Unrecoverable blocker
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:60` — "A tool failed in a way you cannot recover from… Plain text: state what failed, what you tried, what's needed. Leave the task `in_progress`. Stop."
**Interpolated; no direct test.**

### Scenario: Executive decision required
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:61` — "`AskUserQuestion` with 2–4 options and your recommendation labeled `(Recommended)`. Resume on answer."
**Interpolated; no direct test.**

### Scenario: Risky or destructive action
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:62` — "Plain text confirmation prompt — describe the action and ask permission. Do not bury it inside an `AskUserQuestion`."
**Interpolated; no direct test.**

---

## Requirement: Scope integrity

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:92` — "No silent scope expansion… add it via `TaskCreate` (with appropriate `blockedBy`) so it's visible"
- `plugins/sessionkit/skills/drive/SKILL.md:95` — "Never modify task subjects/descriptions to make them easier."

### Scenario: Unplanned sub-work discovered
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:92` — TaskCreate with blockedBy for unplanned sub-tasks.
**Interpolated; no direct test.**

---

## Requirement: Final report

**Sources**
- `plugins/sessionkit/skills/drive/SKILL.md:73-85` — Step 5 defines the completion report format with task count, elapsed time, highlights, and outstanding items

### Scenario: Chain completed
**Source:** `plugins/sessionkit/skills/drive/SKILL.md:73-84` — "When the chain is fully completed (no pending or in_progress tasks remain), output a tight report."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — Drive has no test suite. The behavior is encoded entirely in the SKILL.md directive and validated by the consistency of the directive language.
2. The "one preamble then silence" contract relies on the model following the directive; no runtime enforcement mechanism exists.
3. The distinction between "blocker" and "executive decision" requires model judgment on what constitutes "irrecoverable" vs. "a genuine fork" — this is intentionally left to context.
