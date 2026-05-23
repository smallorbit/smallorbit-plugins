# Suggest Permissions — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Session history location

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:20-29` — Step 1 defines the encoded-cwd path and reads the five most recent JSONL files
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:82` — Constraints: "If session history is unavailable or empty, say so and stop"

### Scenario: History files found
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:24-28` — `ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -5`
**Interpolated; no direct test.**

### Scenario: History unavailable
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:82` — explicit stop constraint.
**Interpolated; no direct test.**

---

## Requirement: Pattern identification across three categories

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:32-39` — Step 2 defines three categories and the 2+ appearances threshold

### Scenario: Bash command pattern
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:33` — "Bash commands — package managers, VCS, language runtimes, project-specific scripts."
**Interpolated; no direct test.**

### Scenario: File edit pattern
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:34` — "File edits — source directories, file globs, config files."
**Interpolated; no direct test.**

### Scenario: MCP tool pattern
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:35` — "MCP tools — any MCP tool approved more than once."
**Interpolated; no direct test.**

---

## Requirement: Scoped suggestions

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:56-59` — Step 3 formats suggestions with one-line rationale, grouped by category
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:80` — Constraints: "Do not suggest wildcard patterns broader than what the evidence supports"

### Scenario: Evidence-bounded suggestion
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:80` — explicit no-over-wildcard constraint with `Bash(*:*)` counter-example.
**Interpolated; no direct test.**

---

## Requirement: Approval gate before applying

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:60-61` — Step 3 ends with AskUserQuestion; step 4 reached only after answer
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:77` — Constraints: "Never write to settings files without explicit user approval"
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:78-79` — "always request approval via the `AskUserQuestion` tool — not prose. A silent wait with no tool call is a defect."

### Scenario: Approval requested
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:60-61` — "call the `AskUserQuestion` tool to request approval."
**Interpolated; no direct test.**

### Scenario: User approves
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:63-69` — "If the user approves some or all suggestions: 1. Read… 2. Merge… 3. Write…"
**Interpolated; no direct test.**

### Scenario: User cancels
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:60` — options include Cancel; step 4 not reached.
**Interpolated from absence; no direct test.**

---

## Requirement: Settings file target

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:63-69` — Step 4 reads existing file, merges, writes back
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:68-69` — "If no `.claude/settings.json` exists, create it with the minimal structure needed."
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:79` — Constraints: "Suggest project-level `.claude/settings.json` by default; offer `settings.local.json` as an alternative"

### Scenario: Settings file absent
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:68-69` — creation with minimal structure.
**Interpolated; no direct test.**

### Scenario: Settings file present
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:63-67` — read + merge + write workflow.
**Interpolated; no direct test.**

---

## Requirement: Completion report

**Sources**
- `plugins/sessionkit/skills/suggest-permissions/SKILL.md:72-74` — Step 5 reports what was added and suggests running again

### Scenario: Permissions applied
**Source:** `plugins/sessionkit/skills/suggest-permissions/SKILL.md:72` — "Report what was added and where."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated** — no test suite covers suggest-permissions behavior.
2. The "approved without hesitation" qualifier (line 39) alongside the 2+ threshold is deliberately subjective — it allows the skill to surface patterns from a single session where the approval cadence indicates strong user intent.
3. The `settings.local.json` alternative (constraint line 79) is the mechanism for keeping personal permissions out of committed project settings.
