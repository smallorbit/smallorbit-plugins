---
name: spec
description: Interview the user to fully understand a change, fix, or feature; develop a structured plan; then file the plan as a GitHub epic with linked child issues.
triggers:
   - "/spec"
   - "spec this out"
   - "spec out"
   - "let's spec"
---

# Spec Skill

Orchestrates the full discuss → interview → plan → file workflow. Accepts any
description of a bug, fix, or feature; interviews the user for detail; builds a
structured plan; then files it as a GitHub epic with linked child issues.

## Input

`$ARGUMENTS` — a freeform description of what to spec. If empty, ask the user
what they want to spec before proceeding.

## Process

### 1. Explore codebase context

Before the first interview question, grep or glob for files relevant to
`$ARGUMENTS` so questions are grounded in the actual code. Run this in the
background while forming the first question batch; do not wait for it. Collect
results before writing the plan in step 3.

### 2. Interview

Use `AskUserQuestion` (1–4 questions per round) to gather:

- **Scope** — what's in, what's explicitly out
- **Behaviour** — expected UX before and after; edge cases
- **Constraints** — performance, a11y, backwards-compat, provider-specific concerns
- **Acceptance criteria** — how will we know it's done?

Challenge assumptions and contradictions. Continue rounds until you have enough
to write a complete, unambiguous plan. Do not proceed to planning until
ambiguities are resolved.

### 3. Write the plan

Synthesise the interview into a structured plan with these sections:

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
Decomposed work items — each becomes a child issue.
Each task: title, category (bug/enhancement/refactor/test/docs), priority (high/medium/low), one-line description.

Always append the following documentation task as the final row, unless the spec is a pure refactor or internal-only change with no user-facing or architectural impact:

| # | Title | Category | Priority | Description |
|---|-------|----------|----------|-------------|
| N | Update documentation | docs | low | Update `README.md` and `CLAUDE.md` to reflect any new settings, behaviours, or architectural changes introduced by this feature |
```

Present the plan inline. Ask for approval before filing any issues. Allow the
user to adjust priorities, remove tasks, or add tasks before proceeding.

### 4. File child issues

Pass the full task list from the plan to `/catalog` in a single call. `/catalog` handles duplicate detection, label creation, and issue body format.

### 5. Create the epic tracking issue

Before creating, check for an existing epic: `gh issue list --search "epic: <title>" --state open`. Skip creation and report the existing issue number if found.

After all child issues are created, create one parent epic issue:

```markdown
## Goal

<one sentence from the plan>

## Background

<from the plan>

## Issues

- [ ] #N title
- [ ] #N title
      ...

## Acceptance Criteria

<from the plan's requirements>
```

- Title format: `epic: <short description>`
- Labels: `epic` (create if missing) + `priority:<level>` matching the highest-priority child

### 6. Report

Output a summary table:

```
Epic:  #N  epic: <title>

| # | Issue | Category | Priority |
|---|-------|----------|----------|
| 1 | #N title | bug | high |
| 2 | #N title | test | medium |
```

## Constraints

- Never create issues without showing the plan and getting approval first
- Never write plan files to disk — the plan lives in the conversation only
- Only create an epic if there are 2 or more child issues — skip step 5 entirely for single-issue plans
- Epic issue must be created last, after all child issue numbers are known
- If `$ARGUMENTS` is empty, ask what to spec before doing anything else
