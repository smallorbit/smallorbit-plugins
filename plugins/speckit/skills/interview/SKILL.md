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

Present the plan inline.

### 4. Hand off

If you were invoked as a sub-skill (e.g. from `/speckit:spec`), return the
structured plan output and stop — do not emit any hand-off suggestion. The
orchestrating skill handles next steps.

If you were invoked standalone, end the response by stating that the plan is
ready to feed into `/speckit:catalog` to file the task list as prioritised,
labelled GitHub issues. Do not file issues from this skill — hand off cleanly.

## Constraints

- Ask 1–4 questions per round — never one-at-a-time, never a wall of questions
- Do not produce a plan until ambiguities are resolved
- Never file GitHub issues from this skill — always hand off to `/speckit:catalog` (or return to the orchestrating skill if invoked as a sub-skill)
- Never write the plan to disk unless the user explicitly asks
- Keep the plan concise — it's a decision record, not an essay
- Output sections must match `/spec` exactly: Goal, Background, Requirements, Out of Scope, Tasks
- Tasks table must include the `Depends On` column — use `—` when a task has no dependencies
