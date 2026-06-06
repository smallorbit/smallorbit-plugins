---
name: spec-baseline
description: Derive an OpenSpec spec.md from an existing codebase (not a proposed change), and optionally produce a companion REFERENCES.md that cites every requirement and scenario back to specific file:line (with an optional read-only audit agent to verify those citations). Use when baselining legacy or existing code as a specification; add REFERENCES.md when you want human-reviewable evidence that a spec reflects real behavior.
triggers:
  - "baseline spec for"
  - "spec from legacy code"
  - "derive spec from existing"
  - "document what X does as a spec"
  - "create a spec for existing code"
  - "baseline the existing"
  - "write a spec based on the code"
  - "extract spec from"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Spec Baseline

Reverse-engineer an OpenSpec `spec.md` from an existing codebase, then produce a
`REFERENCES.md` that makes every derived claim verifiable. Optionally audit the
references with an independent agent.

## Setup note

The OpenSpec validator lives at `scripts/openspec` in this repo. Validation calls use
`bash scripts/openspec validate <capability> --type spec --strict`.

## When to use this vs. `/opsx:propose`

| Situation | Skill |
|---|---|
| Code already exists; you want to capture what it *does* | `/spec-baseline` |
| You want to propose *new* behavior or a change | `/opsx:propose` |

---

## Process

### Step 1 — Identify the scope

Ask the user (or infer from context):
- Which capability or module to baseline (e.g. "tipping", "transfer", "checkout-form")
- Which codebase(s) to read (current repo? a legacy repo? both for comparison?)
- Whether to target a single stack or write stack-agnostically

If the target is a **legacy codebase** being compared to a new one, write the spec
stack-agnostically: no framework names, no component class names, no library-specific
APIs. Behaviors are expressed in domain terms (what the system does, not how).

Also decide **whether to produce `REFERENCES.md`** (Step 4) — it is opt-in, not automatic.

### Choosing whether to produce REFERENCES.md

`REFERENCES.md` is human-reviewable evidence: it cites every requirement and scenario
back to `file:line` so a reviewer can verify the spec reflects real behavior. It is
valuable when that evidence is worth the upkeep, and pure overhead when it is not.

| Produce REFERENCES.md | Skip it |
|---|---|
| Baselining legacy/unfamiliar code you don't fully trust | Code you wrote or know well |
| Comparing a legacy implementation to a new one | A quick internal baseline nobody will audit |
| High-stakes spec where a reviewer needs auditable proof | Spec that will be reviewed against the code directly |
| Source has a real test surface to cite | Instruction-style prose (e.g. `SKILL.md`) with no executable code to cite |

Default to **asking the user** when the situation is ambiguous. When skipping, jump
straight from Step 3 to the end — Steps 4 and 5 do not run, and the spec is the sole
deliverable.

### Step 2 — Read the source

For the target module, read:
1. **Implementation files** — the primary source of behavior
2. **Test files** — tests reveal edge cases and observable contracts the code alone may not
3. **Git history** — `git log --follow -n 10 -- <path>` on key files to surface *why* decisions were made

If the project has an inventory brief (e.g. `openspec/inventory/modules/<name>.md`),
read that first as a map; do not copy it wholesale into the spec.

### Step 3 — Write `openspec/specs/<capability>/spec.md`

Follow the OpenSpec spec format exactly:
```markdown
# <Capability Name>

## Purpose
<1–3 sentences: what problem this capability solves and for whom>

## Requirements

### Requirement: <requirement name>
<Normative requirement text using SHALL/MUST>

#### Scenario: <scenario name>
- **WHEN** <condition>
- **THEN** <expected outcome>
```

Rules:
- One `## Requirements` section; all `### Requirement:` blocks inside it
- Every `### Requirement:` must have at least one `#### Scenario:` (4 hashtags, exact)
- Use SHALL/MUST for normative requirements; avoid "should" or "may"
- **Stack-agnostic:** no framework names, no component class names, no library APIs
- Basket/API field names from the domain model are acceptable (they are the universal contract)
- Validation rules, timing constants, and business logic thresholds belong in the spec

After writing, validate: `bash scripts/openspec validate <capability> --type spec --strict`

### Step 4 — Write `openspec/specs/<capability>/REFERENCES.md` *(optional)*

**Run this step only when references were requested** (see "Choosing whether to produce
REFERENCES.md" under Step 1). If they were not, stop after Step 3 — the spec is the
deliverable, and Step 5 does not run either.

This file is NOT part of the spec (it will not be validated). It is a human-readable
annotation of every requirement and scenario, pointing to the source code.

Structure (mirrors spec.md order):
```markdown
# <Capability Name> — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `<repo-root>/`.
Line numbers verified on <date>.

---

## Requirement: <same name as in spec.md>

**Sources**
- `path/to/file.ts:LINE-RANGE` — <what is at those lines and why it supports the claim>
- `tests/path/test.ts:LINE-RANGE` — `'test name'` verifies <what behavior>

**Notes**
- <Interpretive choices, surprising behaviors, divergence from the new app>

### Scenario: <same name as in spec.md>
**Source:** `path/to/file.ts:LINE` — <specific identifier/expression>.
[Verified by test at line N. | **Interpolated; no direct test.**]
```

At the end, include a `## Cross-cutting interpretive notes` section listing every
scenario or claim that was **interpolated from absence** (no code or test directly
asserts it). Number them. These are the human reviewer's primary checklist.

**Citation discipline:**
- Cite the smallest range that contains the relevant identifier (prefer `file.ts:123`
  over `file.ts:100-200`)
- When a test verifies the claim, include the test citation on the same scenario line
- When no test exists, end with `**Interpolated; no direct test.**` or `**Interpolated from absence.**`

### Step 5 — Spawn the citation audit agent (optional, recommended when Step 4 ran)

Only applies when Step 4 produced a `REFERENCES.md`. After the references file is
written, offer to audit it. If the user agrees, spawn
a **read-only Sonnet agent** with this prompt (fill in the repo path and capability):

> You are auditing a references file to verify source-code citations are accurate.
> Read-only; do not modify files.
>
> **Spec:** `openspec/specs/<capability>/spec.md`
> **References:** `openspec/specs/<capability>/REFERENCES.md`
> **Source repo:** `<absolute path to legacy/source repo>`
>
> For each Source citation: verify the file exists, the line numbers contain what
> the references file claims, and the code substantiates the spec claim. For test
> citations, verify the test actually asserts the claimed behavior. For items in
> "Cross-cutting interpretive notes", verify no direct test coverage exists.
>
> Flag categories: WRONG_FILE, WRONG_LINE (>±5), DRIFT (≤±5), CLAIM_MISMATCH,
> MISSING_CITATION, OVER_CLAIMED_TEST, OVER_FLAGGED_INTERPOLATION,
> UNDER_FLAGGED_INTERPOLATION.
>
> Output: one-line summary (N citations checked / N flagged), then findings grouped
> by category using this shape per finding:
> > **Requirement:** "name" | **Scenario:** "name" (or —)
> > **Citation:** `file.ts:LINE` — "what REFERENCES.md claims"
> > **Issue:** what's actually there
> > **Suggested fix:** corrected range or note
>
> Close with: "OK to trust" (only DRIFT/OVER_FLAGGED are present or none) or
> "Needs revision" (any other category present).

Apply the corrections the agent returns before declaring the references file done.

---

## Constraints

- REFERENCES.md (Step 4) is opt-in — decide per "Choosing whether to produce REFERENCES.md". When references *are* requested, write one entry per requirement and scenario; do not half-produce them
- Never mark a scenario "Verified by test" unless you have read the test and confirmed the assertion
- Always label interpolated claims explicitly — do not present them as verified
- Run `bash scripts/openspec validate --strict` before reporting the spec as complete
- Stack-agnostic means: no React, no Ember, no Glimmer, no TanStack, no ember-concurrency, no framework-specific lifecycle names in the spec body
- The spec is about behavior; the REFERENCES.md is about evidence — keep them separate
- If a legacy codebase is being compared to a new implementation, add a comparison table at the end of the spec (or as a separate `COMPARISON.md`) noting behavioral differences — these are product decisions, not errors

## Output checklist

- [ ] `openspec/specs/<capability>/spec.md` — validates with `bash scripts/openspec validate --strict`
- [ ] References decision made (produced, or skipped with reason)

*If references were produced:*

- [ ] `openspec/specs/<capability>/REFERENCES.md` — one entry per requirement and scenario
- [ ] Cross-cutting interpretive notes section present with numbered items
- [ ] Citation audit run (or explicitly deferred with reason)
- [ ] If audit returned "Needs revision", corrections applied
