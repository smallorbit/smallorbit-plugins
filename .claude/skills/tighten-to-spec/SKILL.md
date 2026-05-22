---
name: tighten-to-spec
description: Audit an implementation artifact (typically a SKILL.md, README, or module file) against its written OpenSpec spec. Surface concrete findings across five categories — non-compliance, overreach, redundancy, bloat, overcomplication — each with file:line citations. Interview the user on which findings to apply, then refactor. The complement to spec-baseline.
triggers:
  - "audit X against the spec"
  - "tighten X to match the spec"
  - "does X conform to the spec"
  - "find drift between spec and implementation"
  - "spec compliance audit"
  - "tighten the implementation"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, AskUserQuestion
---

# Tighten to Spec

Audit an implementation artifact against its written behavioral spec, surface
concrete findings, interview on scope, then apply the approved tightening edits.
The pair to [`spec-baseline`](../spec-baseline/SKILL.md) — baseline produces the
spec, this skill enforces it.

## When to use this

| Situation | Skill |
|---|---|
| You have a spec and an impl, and want to know how well they align | `/tighten-to-spec` |
| You have code but no spec yet | `/spec-baseline` |
| You want a generic 5-dimension quality score (no spec input) | `/polishkit:appraise` |

---

## Process

### Step 1 — Identify the spec and implementation

Confirm (or infer from context):
- **Spec path** — the OpenSpec `spec.md`, typically `openspec/specs/<capability>/spec.md`
- **Implementation path** — the artifact to audit (SKILL.md, README, module file, etc.)

If either is missing or ambiguous, ask before proceeding. Do not invent a spec.

### Step 2 — Read both artifacts

Read the spec end to end first to load the behavioral contract into context.
Then read the implementation top to bottom, noting line numbers as you go —
every finding in step 3 must cite a specific line range.

### Step 3 — Audit across five categories

Walk the spec requirement-by-requirement and scenario-by-scenario, comparing
each to the implementation. Group findings:

1. **Non-compliance** — places where the implementation contradicts, omits, or
   under-specifies a spec requirement. Cite the spec requirement name + impl
   file:line.
2. **Overreach** — places where the implementation adds constraints or
   behaviors not in the spec. For each, note whether the directive belongs in
   project-wide rules (CLAUDE.md, `_shared/` docs) or is a legitimate
   skill-specific extension worth preserving.
3. **Redundancy** — repeated information across sections (the same warning
   stated multiple times; a constraints section that restates the body; a
   reference + inline duplication that drifts).
4. **Bloat** — content that adds no signal (verbose code blocks that should
   reference a canonical doc; sibling descriptions that belong in the README;
   excessive examples; commentary that doesn't change reader behavior).
5. **Overcomplication** — structure that could be simpler (too many labeled
   sections, defensive checks that duplicate framework guarantees, multi-layer
   warnings, prompt scaffolding heavier than the underlying directive).

For every finding, include the implementation file:line. Vague critique is
unactionable.

### Step 4 — Surface suggestions in priority order

After the categorized findings, list concrete tightening suggestions in
priority order. Each suggestion should be actionable in one edit — not "reconsider
the whole thing." Where possible, estimate line savings.

A good suggestion has the shape:
> N. **<one-line action>** — what to replace, what with, and what's saved.

### Step 5 — Interview the user on scope

Use `AskUserQuestion` (max 4 questions per call) for any ambiguous decisions:
- For category findings with non-obvious tradeoffs, present both interpretations
- For "is this overreach or appropriate implementation detail?" cases, ask
- For "remove this restated content" calls, confirm if it might serve a purpose
  (scannability, onboarding)

Skip the interview if the user has already given clear scope ("apply all" /
"apply the top 3" / "just the redundancy fixes").

### Step 6 — Apply the approved changes

- For small, scattered edits, use `Edit`
- For substantial restructuring (more than ~30% of the file), `Write` the new
  version

After each edit, if a validator exists for the spec format, re-run it (e.g.
`bash scripts/openspec validate <capability> --type spec --strict`). The
implementation edit shouldn't touch the spec, but a passing validator confirms
the alignment claim.

Report the line delta (before → after) and confirm every spec scenario still
maps to a directive in the tightened implementation.

---

## Constraints

- Never refactor an artifact without a written spec — the spec is the contract.
  If no spec exists, run `/spec-baseline` first.
- Every finding MUST cite implementation file:line. Vague critique is rejected.
- Never silently expand scope beyond the file under audit. If a sibling file
  looks worse, surface that as a separate suggestion; do not modify it.
- Preserve behavioral coverage. After refactoring, every spec scenario MUST
  still map to a directive in the implementation. If the coverage map would
  break, the edit is wrong.
- Tightening removes; it does not add. Do not introduce new abstractions,
  helper functions, or shared utilities during a tightening pass. Those are
  separate features.
- If the audit produces zero findings, say so explicitly and stop. Manufactured
  churn is worse than a no-op pass.
- Re-validate the spec after refactoring to confirm alignment (the impl edit
  shouldn't touch the spec, but the validator check is the discipline that
  catches accidental drift).

## Output checklist

- [ ] Audit findings grouped into the five categories with file:line citations
- [ ] Priority-ordered suggestions with estimated line savings where applicable
- [ ] Interview turn (or explicit acknowledgement that scope was pre-decided)
- [ ] Edits applied; line delta reported (before → after)
- [ ] Spec validator re-run (if applicable) and still passing
- [ ] Coverage check: every spec scenario still maps to an impl directive
