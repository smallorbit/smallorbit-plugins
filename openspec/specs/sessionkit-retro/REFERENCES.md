# Retro — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Parallel signal collection

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:26-56` — Step 1 collects git activity, JSONL events, task list, and conversation transcript, with "Run all data-collection commands in parallel. Tolerate missing outputs gracefully."

### Scenario: All surfaces available
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:27` — "Run all data-collection commands in parallel."
**Interpolated; no direct test.**

### Scenario: A surface is unavailable
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:27` — "Tolerate missing outputs gracefully — an empty surface is itself a signal."
**Interpolated; no direct test.**

---

## Requirement: Three-bucket synthesis

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:59-88` — Step 2 defines the three buckets with bullet counts and citation discipline
- `plugins/sessionkit/skills/retro/SKILL.md:150-151` — Constraints: "Always identify at least one item per `## What went well` and `## What didn't go well`"

### Scenario: Friction observed
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:67-71` — "What didn't go well" bullets: repeated corrections, hook-blocked, failed commands, stalled tasks.
**Interpolated; no direct test.**

### Scenario: No friction observed
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:68` — "If no friction surfaces at all, emit: _No friction observed this session._"
**Interpolated; no direct test.**

### Scenario: Positive patterns found
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:63-66` — "What went well" bullets. Constraints line 151 requires at least one even for low-friction sessions.
**Interpolated; no direct test.**

---

## Requirement: Recommended actions with delegation targets

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:74-88` — delegation table and cap-at-4 rule with 4th-slot reservation

### Scenario: More than three actionable items
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:88` — "Cap the list at 4 options. If more than 4 items qualify, keep the highest-signal ones. Reserve the 4th option slot for 'Other — I'll handle this manually.'"
**Interpolated; no direct test.**

### Scenario: No matching skill for a pattern
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:83` — "No matching skill | Surface as plain-text guidance only"
**Interpolated; no direct test.**

---

## Requirement: Inline-only output

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:18` — "Output stays entirely inline. No files are written."
- `plugins/sessionkit/skills/retro/SKILL.md:149` — Constraints: "Never write files."

### Scenario: Output is inline
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:18` — explicit no-file constraint.
**Interpolated; no direct test.**

---

## Requirement: User-gated action menu

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:112-122` — Step 4 defines the AskUserQuestion call with multiSelect and "None — I'm done" option
- `plugins/sessionkit/skills/retro/SKILL.md:122` — "Do not proceed to step 5 until the user answers via `AskUserQuestion`."
- `plugins/sessionkit/skills/retro/SKILL.md:151-152` — Constraints: "Never run delegated skills without explicit user selection."

### Scenario: Action menu presented
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:114-121` — AskUserQuestion with multiSelect: true and "None — I'm done" option.
**Interpolated; no direct test.**

### Scenario: User selects actions
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:126-143` — Step 5 announces and invokes each selected skill.
**Interpolated; no direct test.**

### Scenario: User selects none
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:144-145` — "If the user selects 'None — I'm done', skip all invocations and close the retro with a one-line acknowledgement."
**Interpolated; no direct test.**

---

## Requirement: Skill delegation — no absorption

**Sources**
- `plugins/sessionkit/skills/retro/SKILL.md:153-154` — Constraints: "`retro` is a thin reflective layer. It does not absorb `skillit`'s encoding logic."
- `plugins/sessionkit/skills/retro/SKILL.md:155` — "Do not modify `skillit` or any other existing skill."

### Scenario: Skill invoked
**Source:** `plugins/sessionkit/skills/retro/SKILL.md:132-143` — delegation table maps each action to a `Skill(...)` call.
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — Retro has no test suite.
2. The 4th-slot reservation for "Other — I'll handle this manually" is required only when more than 3 actionable items exist — it is not always present.
3. The delegation table (line 78-86) is the authoritative mapping between pattern types and skill invocations; retro's role ends at delegation.
