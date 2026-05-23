# Pickup — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Graceful absent-file handling

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:19-31` — Step 1 checks for the file and stops with a graceful message if absent

### Scenario: Handoff file absent
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:27-31` — "If the file does not exist, fail gracefully: report > No handoff file found… Then stop."
**Interpolated; no direct test.**

### Scenario: Handoff file present
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:19-26` — `cat .sessionkit/HANDOFF.md 2>/dev/null` followed by remaining steps.
**Interpolated; no direct test.**

---

## Requirement: Open-ended section parsing

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:33-36` — "Unknown headings are passed through unmodified — section parsing is open-ended, so any future or legacy section names… are silently ignored."

### Scenario: Unknown heading encountered
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:34-36` — explicit open-ended parsing rule.
**Interpolated; no direct test.**

---

## Requirement: Orientation summary

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:39-46` — Step 3 lists the five areas: Goal, Progress, Git State, Remaining Work, Context
- `plugins/sessionkit/skills/pickup/SKILL.md:108` — Constraints: "Keep the orientation summary concise — surface the essentials, not everything verbatim"

### Scenario: Orientation presented
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:39-46` — five-area summary format.
**Interpolated; no direct test.**

---

## Requirement: Task list hydration — two-pass

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:49-73` — Step 4 defines the full two-pass hydration: locate JSON block, create tasks (pass 1), wire blockedBy (pass 2)

### Scenario: Task list present and parseable
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:56-73` — pass 1 (TaskCreate per pending/in_progress task) + pass 2 (TaskUpdate addBlockedBy).
**Interpolated; no direct test.**

### Scenario: Task list absent or unparseable
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:51-54` — "If no `## Task List` section exists, or the JSON block is absent or unparseable, emit exactly one line… Then skip."
**Interpolated; no direct test.**

### Scenario: Completed tasks skipped
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:64` — "Skip tasks whose `status` is `completed` — they are history."
**Interpolated; no direct test.**

---

## Requirement: Branch mismatch detection

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:75-89` — Step 5 compares branch and suggests checkout without switching automatically

### Scenario: Branch matches
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:87-88` — "Only suggest this when there's a mismatch."
**Interpolated from absence; no direct test.**

### Scenario: Branch mismatch
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:83-86` — "suggest: `git checkout <branch-from-handoff>`" and "Do not switch branches automatically."
**Interpolated; no direct test.**

---

## Requirement: Readiness confirmation via structured prompt

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:91-103` — Step 6 defines the AskUserQuestion format: question text, header, options from Remaining Work, fallback to plain text

### Scenario: Multiple remaining items
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:93-98` — AskUserQuestion with options derived from Remaining Work when 2+ items exist.
**Interpolated; no direct test.**

### Scenario: Fewer than two actionable items
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:99-101` — "If `Remaining Work` has fewer than 2 actionable items, fall back to plain text."
**Interpolated; no direct test.**

---

## Requirement: Read-only operation

**Sources**
- `plugins/sessionkit/skills/pickup/SKILL.md:107` — Constraints: "Never modify `.sessionkit/HANDOFF.md` — this skill is read-only"
- `plugins/sessionkit/skills/pickup/SKILL.md:110` — "Do not automatically re-execute any commands referenced in the handoff — the goal is to orient, not to act"

### Scenario: Handoff file untouched
**Source:** `plugins/sessionkit/skills/pickup/SKILL.md:107` — explicit constraint.
**Interpolated from absence; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — no test suite covers pickup behavior directly.
2. The "do not wire `blocks`" rule (line 72) prevents double-writing the dependency graph; only `blockedBy` is wired in pass 2.
3. The old-ID → new-ID mapping must be maintained in memory across all `TaskCreate` calls before any `TaskUpdate` call in pass 2 — this ordering is implicit in the sequential pass structure.
