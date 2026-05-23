# Roadmap — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Read-only survey

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:26-60` — Step 1 lists all survey commands in parallel
- `plugins/sessionkit/skills/roadmap/SKILL.md:153` — Constraints: "Read-only during steps 1–3. Never mutate the repo, branches, tags, or PRs while planning."

### Scenario: Survey phase
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:26-27` — "Read-only. Run these in parallel."
**Interpolated; no direct test.**

---

## Requirement: State classification

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:64-78` — Step 2 table mapping each signal to a sub-chain entry point with "composable, not exclusive" note

### Scenario: Multiple signals apply
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:64` — "Identify every state signal that applies (composable, not exclusive)."
**Interpolated; no direct test.**

### Scenario: Nothing to ship
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:77` — "Latest release shipped, develop in sync | 'Nothing to ship' — surface and offer alternatives."
**Interpolated; no direct test.**

---

## Requirement: Task chain synthesis

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:80-115` — Step 3 defines the step library, blockedBy wiring, and task field requirements
- `plugins/sessionkit/skills/roadmap/SKILL.md:158` — Constraints: "Use named skills, not raw commands, where possible."

### Scenario: Linear chain produced
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:110-114` — per-task field spec: subject, description, activeForm, blockedBy.
**Interpolated; no direct test.**

### Scenario: Named skill available
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:158` — "A task description that says 'Run `/flowkit:cut`' is unambiguous to drive; a description that pastes the cut script is brittle."
**Interpolated; no direct test.**

---

## Requirement: Single-thread planning

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:156-159` — Constraints: "One chain per invocation. If the survey turns up two unrelated work threads… ask which one to plan."

### Scenario: Two unrelated threads found
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:156-158` — single-thread constraint with example.
**Interpolated; no direct test.**

---

## Requirement: Plan presentation and approval gate

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:117-151` — Steps 4 and 5 define the plan summary format, AskUserQuestion options, and per-answer actions
- `plugins/sessionkit/skills/roadmap/SKILL.md:154` — Constraints: "Tasks created before approval are provisional. If the user picks 'Cancel', delete every task this invocation created."

### Scenario: Approval requested
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:134-143` — AskUserQuestion with four options.
**Interpolated; no direct test.**

### Scenario: User approves and drives
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:148` — "Drive it for me → invoke `Skill('sessionkit:drive')`."
**Interpolated; no direct test.**

### Scenario: User approves manually
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:149` — "I'll drive → print the task IDs and a one-line reminder."
**Interpolated; no direct test.**

### Scenario: User modifies
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:150` — "Modify → prompt the user for what to change. Update the task list. Re-present from step 4."
**Interpolated; no direct test.**

### Scenario: User cancels
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:151` — "`TaskUpdate` with `status: deleted` for every task created. Confirm and exit."
**Interpolated; no direct test.**

---

## Requirement: Canonical release sequence

**Sources**
- `plugins/sessionkit/skills/roadmap/SKILL.md:101-107` — defines the bubble-free release sequence and explains why ship aborts if worktree-agent PRs remain

### Scenario: Epic in flight
**Source:** `plugins/sessionkit/skills/roadmap/SKILL.md:103-104` — "standard chain is: `/swarmkit:merge-stack → verify (manual) → /flowkit:ship-epic → /flowkit:ship`"
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — Roadmap has no test suite.
2. The `flowkit:pipeline-status` preference (line 62-63) is an optimization hint — if not installed, the raw survey commands are used directly.
3. The single-thread constraint (step 1c) means the survey might reveal more than one thread but Roadmap only plans one per invocation; the user runs Roadmap again for other threads.
