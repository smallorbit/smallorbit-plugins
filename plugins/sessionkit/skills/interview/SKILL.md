---
name: interview
description: Interview you in depth to clarify and complete a plan or spec. Challenges inconsistencies, assumptions, and contradictions until the plan is ready to save.
triggers:
  - "/interview"
  - "interview me"
  - "let's talk through this"
  - "flesh out this plan"
  - "help me think through"
argument-hint: [plan-file]
allowed-tools: AskUserQuestion, Read, Glob, Grep, Write, Edit
---

# Interview

Conduct a deep, structured interview to clarify and complete a plan. Challenges inconsistencies, surfaces assumptions, and continues until the plan is unambiguous and ready to write.

## Input

`$ARGUMENTS` — path to an existing plan file to flesh out, or a freeform description of what you want to plan. If empty, ask the user what they want to work through before starting.

## Process

### 1. Load existing context

If `$ARGUMENTS` points to a file that exists, read it before asking any questions. Use its content to inform the interview — don't ask what's already answered.

If `$ARGUMENTS` is a description rather than a file path, use it as the starting point.

If `$ARGUMENTS` is empty, ask:

> What would you like to plan or think through?

### 2. Interview

Use `AskUserQuestion` (1–4 questions per round) to probe for:

- **Scope** — what's in, what's explicitly out
- **Behaviour** — expected UX or outcomes before and after; edge cases
- **Constraints** — performance, security, accessibility, backwards-compatibility, known limitations
- **Decisions** — open questions that must be resolved before work begins
- **Acceptance criteria** — how will we know it's done?

Challenge inconsistencies, assumptions, and contradictions directly. Don't move on from a round until the answers are sufficient to close that dimension. Continue rounds until the plan is complete and unambiguous.

### 3. Save the plan

When the interview is complete, synthesize everything into a structured plan:

```markdown
## Goal
One sentence.

## Background
What exists today and why it's insufficient.

## Requirements
Numbered list of concrete, testable requirements.

## Out of Scope
Explicit exclusions to prevent scope creep.

## Open Questions
Any remaining unknowns that need resolution before work starts (ideally empty).
```

If `$ARGUMENTS` was a file path, write the updated plan back to that file using the Write tool and confirm the path.

If `$ARGUMENTS` was a description (no file path), present the plan inline and ask where to save it, or whether to keep it in the conversation only.

## Constraints

- Never save the plan without asking first if `$ARGUMENTS` was not a file path
- Ask 1–4 questions per round — never one-at-a-time, never a wall of questions
- Do not produce a plan until ambiguities are resolved
- Keep the plan concise — it's a decision record, not an essay
