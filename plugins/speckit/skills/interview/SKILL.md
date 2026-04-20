---
name: interview
description: Interview you in depth to think through a feature, bug, or change and produce a structured plan in speckit format ready to feed into /spec or /catalog. Challenges inconsistencies, assumptions, and contradictions until the plan is unambiguous.
triggers:
  - "/interview"
  - "interview me"
  - "let's talk through this"
  - "help me think through"
  - "think through this"
argument-hint: [description]
allowed-tools: AskUserQuestion, Read, Glob, Grep, Write, Edit
---

> **Sub-skill notice:** This skill is designed to be invoked by `speckit:spec` (step 2) or standalone via `/interview`. If the user typed `/spec`, do not run this skill directly — invoke `speckit:spec` instead so the full orchestration flow runs (interview → plan approval → catalog → epic).

# Interview

Conduct a deep, structured interview to think through a feature, bug, or change. Challenges inconsistencies, surfaces assumptions, and continues until the thinking is unambiguous. Produces a plan in the same format that `/spec` emits, so the output can be piped directly into `/spec` or `/catalog`.

## Input

`$ARGUMENTS` — a freeform description of a feature, bug, or change to think through. If empty, ask the user what they want to work through before starting.

## Process

### 1. Load context

If `$ARGUMENTS` is empty, ask:

> What would you like to think through?

If `$ARGUMENTS` references files or areas of the codebase, grep or glob for relevant files so questions are grounded in the actual code. Run this in the background while forming the first question batch; do not wait for it.

### 2. Interview

Use `AskUserQuestion` (1–4 questions per round) to probe for:

- **Scope** — what's in, what's explicitly out
- **Behaviour** — expected UX or outcomes before and after; edge cases
- **Constraints** — performance, security, accessibility, backwards-compatibility, known limitations
- **Decisions** — open questions that must be resolved before work begins
- **Acceptance criteria** — how will we know it's done?

Challenge inconsistencies, assumptions, and contradictions directly. Don't move on from a round until the answers are sufficient to close that dimension. Continue rounds until the plan is complete and unambiguous.

### 3. Produce the plan

Synthesise the interview into a structured plan with these exact sections:

```
## Goal
One sentence.

## Background
What exists today and why it's insufficient.

## Requirements
Numbered list of concrete, testable requirements.

## Out of Scope
Explicit exclusions to prevent scope creep.

## Tasks
Decomposed work items — each is a candidate child issue.
Each task: title, category (bug/enhancement/refactor/test/docs), priority (high/medium/low), depends-on (task # or — if none), one-line description.

| # | Title | Category | Priority | Depends On | Description |
|---|-------|----------|----------|------------|-------------|
| 1 | ...   | ...      | ...      | —          | ...         |

Always append the following documentation task as the final row, unless the plan is a pure refactor or internal-only change with no user-facing or architectural impact:

| N | Update documentation | docs | low | — | Update `README.md` and `CLAUDE.md` to reflect any new settings, behaviours, or architectural changes introduced by this feature |
```

#### 3a. Consolidation pass (silent)

After drafting the candidate tasks table and before presenting the plan, run a silent consolidation pass. This pass merges over-decomposed tasks so the approval step shows a clean, actionable plan. The user sees only the consolidated result; they can still request splits during approval if needed.

**Merge signals** — merge two tasks if ANY fires:

1. **Same file + same logical change** — both tasks touch only the same single file and address related changes to the same function, section, or config block.
2. **Strict ordering, no standalone value** — one task cannot ship without the other and provides no independent acceptance criteria (e.g. "wire up the X added in task A").
3. **Soft cap on epic size** — after applying signals 1 and 2, if the consolidated task count is still **>4**, run a second merge pass that re-examines the table under looser interpretations of signals 1 and 2. In this pass, prefer broader task descriptions with multiple sub-bullets over fine-grained separate tasks. Stop when no further defensible merges remain — do **not** force the count below 4 if the remaining tasks are genuinely independent (different files, different surfaces, independent acceptance criteria). The soft cap is a prompt to re-examine, not a hard limit.
4. **Docs-only tail merge** — if after the main pass the auto-appended "Update documentation" task is the only remaining non-implementation task AND the remaining implementation task(s) touch the same conceptual surface that the docs would cover, fold the docs task into the implementation task by adding a documentation bullet to its description. This signal only fires when there is one clear implementation task, or a small group of impl tasks touching the same surface — do not apply it when impl work spans multiple unrelated surfaces.

Only merge when a signal clearly applies. Tasks that are legitimately independent — even if related — must not be merged. The goal is to eliminate redundant decomposition, not to collapse distinct work items.

**Merge rules** — when two tasks merge, apply deterministically:

- **Priority** — take the higher value (`high > medium > low`).
- **Category** — take the higher-impact value (`bug > refactor > enhancement > test > docs`).
- **Description** — preserve both originals as sub-bullets so no work item is lost.
- **Dependencies** — remap: if task C depended on B, and A+B merged into A', then C now depends on A'.
- **Numbering** — renumber the resulting table sequentially after all merges are applied.

**Worked example**

*Before consolidation* — two tasks flagged by signal 2 (strict ordering, no standalone value):

| # | Title | Category | Priority | Depends On | Description |
|---|-------|----------|----------|------------|-------------|
| 1 | Add `autoRetry` config option | enhancement | medium | — | Add `autoRetry: boolean` to `config.ts` and wire defaults in `loadConfig()` |
| 2 | Wire `autoRetry` into request handler | enhancement | medium | 1 | Read `autoRetry` from config in `requestHandler.ts` and retry on transient errors |
| 3 | Add retry integration tests | test | low | 2 | Cover retry behaviour in `requestHandler.test.ts` |

Task 2 has no standalone value — it cannot ship without task 1 and its only purpose is to consume what task 1 adds. Signal 2 fires.

*After consolidation* — tasks 1 and 2 merge into a single task; task 3 remaps its dependency:

| # | Title | Category | Priority | Depends On | Description |
|---|-------|----------|----------|------------|-------------|
| 1 | Add and wire `autoRetry` config option | enhancement | medium | — | - Add `autoRetry: boolean` to `config.ts` and wire defaults in `loadConfig()` - Read `autoRetry` from config in `requestHandler.ts` and retry on transient errors |
| 2 | Add retry integration tests | test | low | 1 | Cover retry behaviour in `requestHandler.test.ts` |

Present the plan inline.

### 4. Hand off

**When invoked as a sub-skill** (e.g. from `/speckit:spec`), the final output
of this skill is the structured plan and nothing else. Do NOT emit any
trailing sentence, next-steps paragraph, `/catalog` suggestion, or hand-off
prose. The orchestrating skill owns the handoff — your response ends at the
Tasks table. Any trailing prose is a defect: it bleeds into the orchestrator's
output and strands the user with no approval call.

**When invoked standalone** (via `/interview`), end the response by stating
that the plan is ready to feed into `/speckit:catalog` to file the task list as
prioritised, labelled GitHub issues. Do not file issues from this skill — hand
off cleanly.

## Constraints

- Ask 1–4 questions per round — never one-at-a-time, never a wall of questions
- Do not produce a plan until ambiguities are resolved
- Never file GitHub issues from this skill — always hand off to `/speckit:catalog` (or return to the orchestrating skill if invoked as a sub-skill)
- Never write the plan to disk unless the user explicitly asks
- Keep the plan concise — it's a decision record, not an essay
- Output sections must match `/spec` exactly: Goal, Background, Requirements, Out of Scope, Tasks
- Tasks table must include the `Depends On` column — use `—` when a task has no dependencies
