# speckit-issue — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `sop/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Input Handling

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:20-21` — "`$ARGUMENTS` — a freeform description of the issue. If empty, ask the user what the issue is about before proceeding."

### Scenario: Description provided via arguments
**Source:** `plugins/speckit/skills/issue/SKILL.md:20` — freeform description accepted via `$ARGUMENTS`.
**Interpolated; no direct test.**

### Scenario: Empty arguments prompts for description
**Source:** `plugins/speckit/skills/issue/SKILL.md:21` — "If empty, ask the user what the issue is about before proceeding."
**Interpolated; no direct test.**

---

## Requirement: Issue Drafting

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:30-44` — Step 2 defines derivation of title (under 70 chars), type, priority (default medium), and body structure.
- `plugins/speckit/skills/issue/SKILL.md:38` — body sections: Problem, Why this matters, Suggested fix.

### Scenario: Title derived under 70 characters
**Source:** `plugins/speckit/skills/issue/SKILL.md:33` — "Title: short, specific, under 70 characters."
**Interpolated; no direct test.**

### Scenario: Priority inferred from description
**Source:** `plugins/speckit/skills/issue/SKILL.md:35` — "Priority: high | medium | low (infer from the description; default to medium)."
**Interpolated; no direct test.**

---

## Requirement: Duplicate Check

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:46-50` — Step 3: `gh issue list` for similar titles; flag and ask whether to proceed.

### Scenario: Similar existing issue flagged
**Source:** `plugins/speckit/skills/issue/SKILL.md:49-50` — "If a similar issue exists, flag it and ask whether to proceed with a new one."
**Interpolated; no direct test.**

### Scenario: No similar issues proceeds without prompting
**Source:** `plugins/speckit/skills/issue/SKILL.md:46-50` — implied: check runs, no match found, no interruption.
**Interpolated from absence.**

---

## Requirement: Preview Approval Gate

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:52-86` — Step 4: show draft and call `AskUserQuestion` in the same turn; wrong/right shape examples.
- `plugins/speckit/skills/issue/SKILL.md:62` — "Never end the turn after the preview without the tool call."
- `plugins/speckit/skills/issue/SKILL.md:86` — Pre-end self-check.

### Scenario: Preview and approval call in same turn
**Source:** `plugins/speckit/skills/issue/SKILL.md:62-83` — "In a single assistant turn, emit (a) the preview above and (b) an `AskUserQuestion` call."
**Interpolated; no direct test.**

### Scenario: Adjustment request loops back
**Source:** `plugins/speckit/skills/issue/SKILL.md:88-89` — "If the user selects an adjust or cancel option, loop back (update the draft or abort) before re-asking."
**Interpolated; no direct test.**

---

## Requirement: Label Provisioning

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:91-93` — Step 5: check `gh label list` and create missing labels before filing.

### Scenario: Missing labels created before filing
**Source:** `plugins/speckit/skills/issue/SKILL.md:91-93` — "Check `gh label list` and create any missing labels (type + priority) before filing."
**Interpolated; no direct test.**

---

## Requirement: Hash Token Safety

**Sources**
- `plugins/speckit/skills/issue/SKILL.md:108-111` — constraint: never write `#<number>` tokens unless intentional cross-references; strip or rewrite tokens from `$ARGUMENTS`.

### Scenario: Hash tokens from arguments rewritten
**Source:** `plugins/speckit/skills/issue/SKILL.md:108-111` — explicit constraint: "Strip or rewrite any such token inherited from `$ARGUMENTS` before filing."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **All scenarios interpolated from absence of tests** — speckit/issue has no automated test suite. All behavioral claims are derived from reading the SKILL.md prose.

2. **Suggested fix omission** — Line 38 notes "omit [Suggested fix] if unknown." This edge case was not elevated to a separate scenario because it is a drafting hint, not a behavioral requirement with distinct outcomes.

3. **Duplicate check scope** — Step 3 checks only open issues (`--state open`). Closed issues with similar titles are not flagged. This is a deliberate scope limit in the skill (line 47 specifies `--state open`).
