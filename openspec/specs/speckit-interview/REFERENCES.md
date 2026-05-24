# speckit-interview — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `sop/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Input Handling

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:22-23` — `$ARGUMENTS` is the freeform description; if empty, ask before starting.
- `plugins/speckit/skills/interview/SKILL.md:28-30` — explicit empty-argument handler: ask "What would you like to think through?"

### Scenario: Description provided via arguments
**Source:** `plugins/speckit/skills/interview/SKILL.md:22` — "`$ARGUMENTS` — a freeform description of a feature, bug, or change to think through."
**Interpolated; no direct test.**

### Scenario: Empty arguments prompts for topic
**Source:** `plugins/speckit/skills/interview/SKILL.md:28-30` — asks "What would you like to think through?" when arguments empty.
**Interpolated; no direct test.**

---

## Requirement: Codebase Grounding

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:32-34` — "If `$ARGUMENTS` references files or areas of the codebase, grep or glob for relevant files so questions are grounded in the actual code. Run this in the background while forming the first question batch."

### Scenario: Relevant files fetched in background
**Source:** `plugins/speckit/skills/interview/SKILL.md:32-34` — background grep/glob without blocking first questions.
**Interpolated; no direct test.**

---

## Requirement: Multi-Round Interview

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:36-44` — Step 2 defines the five probing dimensions (scope, behaviour, constraints, decisions, acceptance criteria) and the continuation rule.
- `plugins/speckit/skills/interview/SKILL.md:134` — "Ask 1–4 questions per round."
- `plugins/speckit/skills/interview/SKILL.md:43-44` — "Challenge inconsistencies, assumptions, and contradictions directly."

### Scenario: Questions sent 1–4 per round
**Source:** `plugins/speckit/skills/interview/SKILL.md:134` — constraint: "Ask 1–4 questions per round — never one-at-a-time, never a wall of questions."
**Interpolated; no direct test.**

### Scenario: Interview continues until unambiguous
**Source:** `plugins/speckit/skills/interview/SKILL.md:44` — "Continue rounds until the plan is complete and unambiguous."
**Interpolated; no direct test.**

### Scenario: Inconsistencies challenged directly
**Source:** `plugins/speckit/skills/interview/SKILL.md:43` — "Challenge inconsistencies, assumptions, and contradictions directly."
**Interpolated; no direct test.**

---

## Requirement: Structured Plan Production

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:46-74` — Step 3 specifies all five required sections and the Tasks table schema.
- `plugins/speckit/skills/interview/SKILL.md:71-74` — Documentation task auto-appended unless pure refactor.
- `plugins/speckit/skills/interview/SKILL.md:139` — "Output sections must match `/spec` exactly: Goal, Background, Requirements, Out of Scope, Tasks."

### Scenario: Plan contains all five required sections
**Source:** `plugins/speckit/skills/interview/SKILL.md:50-66` — Goal, Background, Requirements, Out of Scope, Tasks sections defined with their content shapes.
**Interpolated; no direct test.**

### Scenario: Documentation task appended unless pure refactor
**Source:** `plugins/speckit/skills/interview/SKILL.md:71-74` — auto-appended "Update documentation" row unless pure refactor or internal-only change.
**Interpolated; no direct test.**

### Scenario: Tasks table includes Depends On column
**Source:** `plugins/speckit/skills/interview/SKILL.md:64-70` — Tasks table schema with `Depends On` column; `—` when no dependency.
**Interpolated; no direct test.**

---

## Requirement: Silent Task Consolidation

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:76-115` — Step 3a defines the four merge signals, merge rules, and a worked example.
- `plugins/speckit/skills/interview/SKILL.md:78` — "The user sees only the consolidated result."
- `plugins/speckit/skills/interview/SKILL.md:89-95` — Merge rules: priority (higher wins), category (higher-impact wins), description (sub-bullets), dependencies (remapped).

### Scenario: Same-file same-change tasks merged
**Source:** `plugins/speckit/skills/interview/SKILL.md:81-82` — Signal 1: same file + same logical change.
**Interpolated; no direct test.**

### Scenario: Strict-ordering no-standalone-value tasks merged
**Source:** `plugins/speckit/skills/interview/SKILL.md:83-84` — Signal 2: strict ordering with no independent acceptance criteria.
**Interpolated; no direct test.**

### Scenario: Soft cap re-examination when task count exceeds four
**Source:** `plugins/speckit/skills/interview/SKILL.md:85-88` — Signal 3: soft cap triggers a second pass; does not force count below 4 if remaining tasks are independent.
**Interpolated; no direct test.**

### Scenario: Priority and category resolved deterministically on merge
**Source:** `plugins/speckit/skills/interview/SKILL.md:89-95` — merge rule table: priority takes higher, category takes higher-impact.
**Interpolated; no direct test.**

---

## Requirement: Handoff Behaviour

**Sources**
- `plugins/speckit/skills/interview/SKILL.md:118-130` — Step 4 defines sub-skill vs. standalone handoff behavior.
- `plugins/speckit/skills/interview/SKILL.md:123-125` — "Do NOT emit any trailing sentence, next-steps paragraph, `/catalog` suggestion, or hand-off prose" when invoked as sub-skill.
- `plugins/speckit/skills/interview/SKILL.md:127-130` — Standalone mode states plan is ready for `/speckit:catalog`.

### Scenario: Sub-skill invocation produces plan only
**Source:** `plugins/speckit/skills/interview/SKILL.md:122-125` — response ends at Tasks table with no trailing prose.
**Interpolated; no direct test.**

### Scenario: Standalone invocation states catalog handoff
**Source:** `plugins/speckit/skills/interview/SKILL.md:127-130` — states plan is ready to feed into `/speckit:catalog`.
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **All scenarios interpolated from absence of tests** — speckit/interview has no automated test suite. All behavioral claims are derived from reading the SKILL.md prose.

2. **Sub-skill notice at top of file** — Line 14 contains a sub-skill notice warning that `/spec` should invoke `speckit:spec`, not this skill directly. This is a routing guard, not a behavioral requirement, and is not captured in the spec.

3. **Soft cap is not a hard limit** — Signal 3 (line 85-88) explicitly states the soft cap "is a prompt to re-examine, not a hard limit" and stops when no further defensible merges remain. The spec captures this nuance in the scenario text.

4. **Docs-only tail merge (Signal 4)** — `plugins/speckit/skills/interview/SKILL.md:85-88` describes Signal 4 (fold docs task into impl when conditions are met). This was not elevated to a standalone requirement because it is a secondary refinement of the consolidation pass, not a separate behavioral surface.
