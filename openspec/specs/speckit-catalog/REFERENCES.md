# speckit-catalog — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `sop/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Finding Extraction

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:32-43` — Step 1 defines parsing into discrete findings with title, category, severity, body fields.
- `plugins/speckit/skills/catalog/SKILL.md:12-18` — Input section defines the three source precedence order: explicit arguments, conversation context, file path, then ask.

**Notes**
- Category values are enumerated at line 36 (bug/enhancement/refactor/documentation/hygiene).
- Severity maps to `priority` in the filing step; line 36 gives the three levels.

### Scenario: Explicit input parsed into findings
**Source:** `plugins/speckit/skills/catalog/SKILL.md:13` — first precedence: explicit input in `$ARGUMENTS`.
**Interpolated; no direct test.**

### Scenario: Conversation context used when arguments empty
**Source:** `plugins/speckit/skills/catalog/SKILL.md:15` — second precedence: earlier conversation containing structured findings.
**Interpolated; no direct test.**

### Scenario: File path resolved to findings
**Source:** `plugins/speckit/skills/catalog/SKILL.md:16-17` — third precedence: if `$ARGUMENTS` is a path, read and extract.
**Interpolated; no direct test.**

### Scenario: No findings available
**Source:** `plugins/speckit/skills/catalog/SKILL.md:18` — "If no findings are available, ask the user what to catalog."
**Interpolated; no direct test.**

---

## Requirement: Phase Consolidation

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:44-55` — Step 1.5 defines the default consolidation rule: same phase + shared scope + no inter-dependency → merge into one issue with checklist body.
- `plugins/speckit/skills/catalog/SKILL.md:55` — `--split` disables consolidation entirely.
- `plugins/speckit/skills/catalog/SKILL.md:48-50` — "Shared scope" definition.
- `plugins/speckit/skills/catalog/SKILL.md:50-52` — "No inter-dependency" definition and counter-example.

### Scenario: Same-phase same-scope findings consolidated
**Source:** `plugins/speckit/skills/catalog/SKILL.md:46-54` — consolidation rule with resulting issue shape.
**Interpolated; no direct test.**

### Scenario: Split flag bypasses consolidation
**Source:** `plugins/speckit/skills/catalog/SKILL.md:55` — `--split` disables and files one issue per row.
**Interpolated; no direct test.**

### Scenario: Findings with inter-dependencies stay separate
**Source:** `plugins/speckit/skills/catalog/SKILL.md:50-52` — rows with explicit ordering dependencies stay split.
**Interpolated; no direct test.**

---

## Requirement: Consolidation Summary

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:57-74` — Step 1.6 defines the pre-file consolidation summary and its exact format.
- `plugins/speckit/skills/catalog/SKILL.md:73-74` — Summary prints even under `--auto`.

### Scenario: Summary printed before catalog table
**Source:** `plugins/speckit/skills/catalog/SKILL.md:57-66` — one line per phase format with rows → issues and reason.
**Interpolated; no direct test.**

### Scenario: Split mode summary
**Source:** `plugins/speckit/skills/catalog/SKILL.md:68-71` — `--split` produces a single summary line.
**Interpolated; no direct test.**

---

## Requirement: Label Provisioning

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:77-105` — Step 2 covers label detection and creation, including the epic label provisioning block.
- `plugins/speckit/skills/catalog/SKILL.md:88-103` — Epic label provisioning: create if missing, warn and confirm if already present.

### Scenario: Missing category or priority labels created
**Source:** `plugins/speckit/skills/catalog/SKILL.md:82-85` — create missing category and priority labels.
**Interpolated; no direct test.**

### Scenario: Epic label created when slug supplied and missing
**Source:** `plugins/speckit/skills/catalog/SKILL.md:90-96` — `gh label create` with color `5319E7` when label is missing.
**Interpolated; no direct test.**

### Scenario: Existing epic label requires confirmation before reuse
**Source:** `plugins/speckit/skills/catalog/SKILL.md:97-103` — warning emitted and explicit approval required before reuse.
**Interpolated; no direct test.**

---

## Requirement: Catalog Approval Gate

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:107-156` — Step 3 specifies table shape, epic header, and the same-turn `AskUserQuestion` contract.
- `plugins/speckit/skills/catalog/SKILL.md:129` — `--auto` skips the approval step.
- `plugins/speckit/skills/catalog/SKILL.md:131-156` — Wrong/right shape examples documenting the same-turn requirement.

### Scenario: Catalog table and approval call in same turn
**Source:** `plugins/speckit/skills/catalog/SKILL.md:131-154` — "The catalog table and the `AskUserQuestion` approval call must be emitted in the same assistant turn."
**Interpolated; no direct test.**

### Scenario: Auto flag bypasses approval
**Source:** `plugins/speckit/skills/catalog/SKILL.md:129` — "If `--auto` was passed in `$ARGUMENTS`, skip the approval step."
**Interpolated; no direct test.**

### Scenario: Epic label column shown in catalog table
**Source:** `plugins/speckit/skills/catalog/SKILL.md:117-127` — table includes epic label on every row when epic slug is active.
**Interpolated; no direct test.**

---

## Requirement: Sequential Issue Creation

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:168-180` — Step 4: create sequentially in priority order, never parallelize, capture URL immediately.
- `plugins/speckit/skills/catalog/SKILL.md:169-172` — Epic label applied to every issue in batch.

### Scenario: Issues created sequentially in priority order
**Source:** `plugins/speckit/skills/catalog/SKILL.md:176-179` — "Create issues sequentially (one at a time) in priority order (high first)."
**Interpolated; no direct test.**

### Scenario: Epic label applied to every issue in batch
**Source:** `plugins/speckit/skills/catalog/SKILL.md:169-172` — `--label "epic:<slug>"` on every `gh issue create` when slug is active.
**Interpolated; no direct test.**

---

## Requirement: Title–Number Verification

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:182-196` — Step 4.5: fetch each issue title via `gh issue view` and assert match.
- `plugins/speckit/skills/catalog/SKILL.md:193-196` — Mismatch halts and reports before passing numbers downstream.

### Scenario: Created issue titles verified
**Source:** `plugins/speckit/skills/catalog/SKILL.md:182-191` — verification loop with `gh issue view --json title`.
**Interpolated; no direct test.**

### Scenario: Mismatch halts reporting
**Source:** `plugins/speckit/skills/catalog/SKILL.md:193-196` — "halt and report — do not pass unverified numbers to downstream steps."
**Interpolated; no direct test.**

---

## Requirement: Handoff Block Emission

**Sources**
- `plugins/speckit/skills/catalog/SKILL.md:198-234` — Step 5 report section and Handoff Contract define `spec-handoff` fenced block shape, schema, placement rule, and conditional emission.
- `plugins/speckit/skills/catalog/SKILL.md:208` — "emit the handoff block immediately after the results table, then stop."
- `plugins/speckit/skills/catalog/SKILL.md:234` — "nothing follows the closing fence."

### Scenario: Handoff block emitted after epic-mode issue table
**Source:** `plugins/speckit/skills/catalog/SKILL.md:212-222` — fenced `spec-handoff` block with `filed`, `epic_slug`, `next_phase` fields.
**Interpolated; no direct test.**

### Scenario: Handoff block omitted without epic flag
**Source:** `plugins/speckit/skills/catalog/SKILL.md:238-240` — "When `--epic <slug>` is NOT passed, this block is omitted entirely."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **All scenarios interpolated from absence of tests** — speckit/catalog has no automated test suite. Every scenario is derived from reading the SKILL.md prose and verified by structural analysis of the skill's process steps. No test file exists to cross-verify any behavioral claim.

2. **`--auto` and consolidation summary interaction** — Line 73-74 explicitly states the summary prints even under `--auto`. This is a non-obvious design choice (auto bypasses approval but not the summary) worth flagging for reviewers.

3. **Epic label confirmation fires at most once** — Line 103 states "This prompt fires at most once per catalog invocation." This deduplication behavior is documented in the skill but has no test coverage.

4. **Downstream number safety** — The title–number verification step (step 4.5) exists specifically because parallel `gh issue create` calls scramble URL↔title mapping. This is the stated rationale for sequential creation at line 177.
