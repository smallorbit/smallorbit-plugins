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

Invoke `/speckit:interview` as a sub-skill, passing the freeform description from
`$ARGUMENTS` as its input. Do not run inline `AskUserQuestion` rounds yourself —
delegate the entire interview to `/speckit:interview` and wait for it to complete.

When `/speckit:interview` returns, collect its structured output. The output will
contain the following sections, which become the basis for the plan in step 3:

- **Goal** — one-sentence summary
- **Background** — current state and why it's insufficient
- **Requirements** — numbered list of concrete, testable requirements
- **Out of Scope** — explicit exclusions
- **Tasks** — decomposed work items

Do not proceed to step 3 until `/speckit:interview` has produced a complete,
unambiguous output with all five sections present.

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
Each task: title, category (bug/enhancement/refactor/test/docs), priority (high/medium/low), depends-on (task # or — if none), one-line description.

Always append the following documentation task as the final row, unless the spec is a pure refactor or internal-only change with no user-facing or architectural impact:

| # | Title | Category | Priority | Depends On | Description |
|---|-------|----------|----------|------------|-------------|
| N | Update documentation | docs | low | — | Update `README.md` and `CLAUDE.md` to reflect any new settings, behaviours, or architectural changes introduced by this feature |
```

Present the plan inline. End the plan with an explicit approval prompt — for example: "Approve and file issues? Reply with any changes to priorities, tasks, or scope." Do not proceed to step 4 until the user responds. Allow the user to adjust priorities, remove tasks, or add tasks before proceeding.

### 4. File child issues

Pass the full task list from the plan to `/catalog` in a single call. `/catalog` handles duplicate detection, label creation, and issue body format.

Do not instruct `/catalog` to embed `Depends on #N` lines (or any other `#<number>` task-reference) in issue bodies. GitHub auto-links `#N` tokens, so a body that says "Depends on task #3" will link to unrelated issue 3 in the repo. Task-to-task dependencies are wired in step 5 via the native GitHub blocked-by API — keep them out of the issue body.

### 5. Create the epic tracking issue

Before creating, check for an existing epic: `gh issue list --search "epic: <title>" --state open`. Skip creation and report the existing issue number if found.

After all child issues are created, create one parent epic issue:

```markdown
## Goal

<one sentence from the plan>

## Background

<from the plan>

## Acceptance Criteria

<from the plan's requirements>
```

- Title format: `epic: <short description>`
- Labels: `epic` (create if missing) + `priority:<level>` matching the highest-priority child
- Do **not** include an issues checklist — child issues are linked via GitHub's native sub-issue relationship (added in the next step)

After creating the epic, wire up relationships:

1. **Add sub-issues**: For each child issue, add it as a sub-issue of the epic:
   ```bash
   gh api repos/{owner}/{repo}/issues/{epic_number}/sub_issues \
     -X POST -F sub_issue_id={child_issue_id}
   ```
   Use the numeric `id` (not the issue number) — fetch it from `gh issue view {number} --json id`.

2. **Wire blocked-by relationships**: For each task with a `Depends On` value in the plan, set the GitHub blocked-by relationship:
   ```bash
   gh api repos/{owner}/{repo}/issues/{blocked_number}/dependencies/blocked_by \
     -X POST -F issue_id={blocking_issue_id}
   ```
   Use `-F` (not `-f`) to pass integers. Map task numbers to issue IDs from the created issues.

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

- After presenting a plan or draft, always end with an explicit approval question. Silent waits are a defect.
- Never create issues without showing the plan and getting approval first
- Never write plan files to disk — the plan lives in the conversation only
- Only create an epic if there are 2 or more child issues — skip step 5 entirely for single-issue plans
- Epic issue must be created last, after all child issue numbers are known
- If `$ARGUMENTS` is empty, ask what to spec before doing anything else
- Never invoke `speckit:interview` directly in response to a user typing `/spec` or triggering this skill. `speckit:interview` is a sub-skill called from within step 2 of this skill — it is never a substitute for `speckit:spec`. If you find yourself about to invoke `speckit:interview` as a top-level response to `/spec`, stop and invoke `speckit:spec` instead.
