# Appraise — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `repo-root/`.
Line numbers verified on 2026-05-22.

---

## Requirement: Scope survey

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:195-212` — `## Workflow` section defines the three scope tiers (single file / pasted code, directory or module, full repo) and the representative-sampling approach for large scopes
- `plugins/polishkit/skills/appraise/SKILL.md:200-204` — "For repo-wide or module assessments, start with a structural survey" — survey steps: directory tree, entry points, domain/infrastructure/test identification, read a representative sample

**Notes**
- The "representative sample — don't try to read every file" constraint is explicit and intentional

### Scenario: Single file scope
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:197-198` — "If it's a single file or pasted code → assess that directly"
**Interpolated; no direct test.**

### Scenario: Repository or module scope
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:200-207` — full structural survey workflow for non-single-file scopes.
**Interpolated; no direct test.**

---

## Requirement: Language detection and idiomatic lens

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:17-28` — `## Supported Languages` section lists C#, Go, Python, TypeScript, React, Next.js and states "applying both universal principles and language-specific idiomatic standards"
- `plugins/polishkit/skills/appraise/SKILL.md:207` — `## Workflow` step 3: "Detect the language(s) in use and activate the appropriate idiomatic lens."

**Notes**
- The specific languages supported (C#, Go, Python, TypeScript, React, Next.js) are listed in the implementation; the spec abstracts these as "detected language + associated framework" to remain stack-agnostic. The enumeration belongs here in REFERENCES.md.

### Scenario: Language detected
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:207` — "Detect the language(s) in use and activate the appropriate idiomatic lens."
**Interpolated; no direct test.**

---

## Requirement: Five-dimension scoring

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:32-127` — `## The Five Dimensions` section defines all five dimensions with 1–10 score anchors
- `plugins/polishkit/skills/appraise/SKILL.md:142-148` — `## Scoring Formula` section with the exact weighted formula and rounding instruction
- `plugins/polishkit/skills/appraise/SKILL.md:150-161` — `## Overall Verdict Tiers` table mapping score ranges to verdicts

**Notes**
- Dimension weights: Architecture 30%, Naming 25%, Algorithmic Elegance 20%, Testability 15%, Idiomatic Consistency 10%

### Scenario: Overall score computed
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:142-148` — the scoring formula block, rounding instruction included.
**Interpolated; no direct test.**

### Scenario: Verdict tier assigned
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:150-161` — the tier table with five ranges.
**Interpolated; no direct test.**

---

## Requirement: Always-flag violations

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:128-139` — `## Always-Flag Violations` table listing five violation types: god classes, magic numbers/strings, comments that restate code, functions >~30 lines, files >~300 lines
- `plugins/polishkit/skills/appraise/SKILL.md:183-188` — `### Violations` subsection of Report Structure: "List any always-flag violations found / Reference specific files/lines"

### Scenario: God class present
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:131` — "God classes / god objects — A class doing too much is the antithesis of clean architecture."
**Interpolated; no direct test.**

### Scenario: Oversized function present
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:135` — "Functions exceeding ~30 lines — Long functions almost always do more than one thing."
**Interpolated; no direct test.**

### Scenario: No violations found
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:183-188` — the Violations section is always present in the report structure; content is the findings or absence thereof.
**Interpolated from absence** — the SKILL.md does not explicitly state what to write when no violations are found; the spec's "states that no violations were found" behavior is inferred.

---

## Requirement: Report structure and length

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:163-191` — `## Report Structure` defines the five-section order and content expectations for each
- `plugins/polishkit/skills/appraise/SKILL.md:14-15` — length cap: "The entire report must stay under **500 lines**. Brevity is itself a form of elegance."
- `plugins/polishkit/skills/appraise/SKILL.md:165-172` — `### Executive Summary` required elements: score, verdict, one-sentence characterization, most beautiful thing, most impactful improvement
- `plugins/polishkit/skills/appraise/SKILL.md:173-177` — `### Beauty Highlights` 2–5 instances with principle named
- `plugins/polishkit/skills/appraise/SKILL.md:218` — "Stay under 500 lines total. Be precise."

### Scenario: Sections appear in prescribed order
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:163-191` — the five sections are listed in the prescribed order.
**Interpolated; no direct test.**

### Scenario: Report stays under length limit
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:14-15` and `plugins/polishkit/skills/appraise/SKILL.md:218` — two explicit 500-line cap statements.
**Interpolated; no direct test.**

---

## Requirement: Read-only operation

**Sources**
- `plugins/polishkit/skills/appraise/SKILL.md:1-3` — description frontmatter: "Produces a scored report" — no mention of file changes
- `plugins/polishkit/skills/appraise/SKILL.md:193-218` — `## Workflow` section: all steps are read/survey/score/produce-report with no write, commit, push, or PR creation steps present

**Notes**
- The read-only constraint is interpolated from absence — the SKILL.md contains no write, edit, commit, or push instructions. There is no explicit "do not modify files" statement.

### Scenario: Assessment completes
**Source:** `plugins/polishkit/skills/appraise/SKILL.md:193-218` — the entire workflow has no file-write steps.
**Interpolated from absence** — read-only behavior is defined by the absence of write operations in the workflow, not by an explicit prohibition.

---

## Cross-cutting interpretive notes

1. **Read-only is interpolated from absence, not stated.** The SKILL.md never says "do not modify files" — the read-only constraint is inferred from the complete absence of write/edit/commit/push steps in the workflow. A future change adding a step with side effects would not contradict an explicit prohibition. This is the primary claim requiring human reviewer attention.

2. **"No violations found" messaging is interpolated.** The SKILL.md specifies the Violations section must exist in the report structure and must reference specific files/lines, but does not define what to write when nothing is found. The spec's "states that no violations were found" wording is an interpretation of the intent.

3. **No test coverage exists for any scenario.** Appraise has no test suite. All scenarios are interpolated from the skill's prompt instructions.

4. **500-line cap is a behavioral commitment.** The cap appears twice (lines 14–15 and 218) with "brevity is itself a form of elegance" framing. This is a deliberate quality signal, not just a practicality — worth preserving in any future rewrites of the skill.
