# Skillit — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Session reflection

**Sources**
- `plugins/sessionkit/skills/skillit/SKILL.md:19-31` — Step 1 reviews conversation history for five pattern types and requires identifying at least one candidate
- `plugins/sessionkit/skills/skillit/SKILL.md:79` — Constraints: "Identify at least one candidate before concluding — never report 'nothing found'"

### Scenario: Candidate identified
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:79` — explicit constraint requiring at least one candidate.
**Interpolated; no direct test.**

---

## Requirement: Existing library survey

**Sources**
- `plugins/sessionkit/skills/skillit/SKILL.md:33-44` — Step 2 scans three paths for existing skills and reads name/description front matter

### Scenario: Overlap found
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:43` — "Surface any close matches to the user before proposing something new."
**Interpolated; no direct test.**

### Scenario: No overlap found
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:43` — absence of close match implies creating a new skill (step 3 option 1).
**Interpolated from absence; no direct test.**

---

## Requirement: Findings presentation

**Sources**
- `plugins/sessionkit/skills/skillit/SKILL.md:46-57` — Step 3 defines the three-part description (what/why/overlap) and the three options

### Scenario: Findings presented
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:46-56` — per-candidate description format and create/modify/skip options.
**Interpolated; no direct test.**

---

## Requirement: Approval-gated skill creation

**Sources**
- `plugins/sessionkit/skills/skillit/SKILL.md:59-73` — Step 4 creates file only on user agreement, at user-specified path, with required sections
- `plugins/sessionkit/skills/skillit/SKILL.md:80` — Constraints: "Never create a skill file without user approval"
- `plugins/sessionkit/skills/skillit/SKILL.md:83` — Constraints: "Skill names must be lowercase kebab-case"

### Scenario: User approves creation
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:59-73` — "On user agreement, create the skill file."
**Interpolated; no direct test.**

### Scenario: User declines
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:55` — "3. Skip — not worth encoding yet" — step 4 is not reached.
**Interpolated from absence; no direct test.**

---

## Requirement: Completion confirmation

**Sources**
- `plugins/sessionkit/skills/skillit/SKILL.md:75-76` — Step 5 reports the absolute path and suggests running again

### Scenario: Skill written
**Source:** `plugins/sessionkit/skills/skillit/SKILL.md:75` — "Report the absolute path of the file written."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — Skillit has no test suite.
2. The "at least one candidate" requirement (constraint line 79) means Skillit will surface something even if the session was routine — this is intentional to keep the habit of skill library growth.
3. The skill file must paths (line 63-64) offer both user-global (`~/.claude/skills/`) and project-local (`.claude/skills/`) as valid targets; the user chooses or is prompted.
