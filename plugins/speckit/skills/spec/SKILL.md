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

### 2.5. Derive the epic slug

Only run this step if the plan will produce an epic — i.e. there are 2 or more
tasks. For single-issue plans, skip slug derivation entirely and omit the
`Epic label:` line from the plan preview in step 3.

Derive a short, epic-scoped slug from the working epic title using these rules:

- Lowercase, kebab-case (words separated by single hyphens)
- Strip filler words: `the`, `a`, `an`, `enhance`, `add`, `update`, `to`, `for`, `of`, `in`
- Cap the slug at 30 characters after the `epic:` prefix (do not count the prefix)
- The final label is `epic:<slug>`

Example: `enhance the catalog skill to apply epic-specific labels` → `epic:catalog-skill-apply-epic-specific-labels` → trimmed to 30 chars → `epic:catalog-epic-labels`.

The derived slug is a proposal — the user reviews and may edit it during plan
approval in step 3. The approved slug is the **single source of truth**: it
flows into both the catalog handoff (step 4, applied to every child issue) and
the epic tracking issue (step 5, applied as a label on the parent).

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

## Epic label
epic:<slug derived in step 2.5>

## Tasks
Decomposed work items — each becomes a child issue.
Each task: title, category (bug/enhancement/refactor/test/docs), priority (high/medium/low), depends-on (task # or — if none), one-line description.

Always append the following documentation task as the final row, unless the spec is a pure refactor or internal-only change with no user-facing or architectural impact:

| # | Title | Category | Priority | Depends On | Description |
|---|-------|----------|----------|------------|-------------|
| N | Update documentation | docs | low | — | Update `README.md` and `CLAUDE.md` to reflect any new settings, behaviours, or architectural changes introduced by this feature |
```

Include the `## Epic label` section **only when the plan produces an epic** (2+ tasks). Omit it for single-issue plans. Render the derived label as a single, editable line, for example: `Epic label: epic:catalog-epic-labels`.

Present the plan inline. Then call the `AskUserQuestion` tool to request approval — a single question such as "Approve this plan and file the issues?" with options like `Approve and file issues`, `Edit epic label`, `Adjust priorities / tasks`, and `Cancel`. Do not proceed to step 4 until the user has answered via `AskUserQuestion` — prose-only prompts like "reply with any changes" are not sufficient, since they don't surface an expected input in the UI. If the user selects an adjust, edit-label, or cancel option, loop back (update the plan, revise the slug, or abort) before re-asking.

The slug the user approves in this step is the single source of truth for the epic label and must be used verbatim in step 4 (catalog handoff for children) and step 5 (epic tracking issue).

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
- Labels: `epic` (create if missing) + `epic:<slug>` (see label-provisioning rules below) + `priority:<level>` matching the highest-priority child
- Do **not** include an issues checklist — child issues are linked via GitHub's native sub-issue relationship (added in the next step)

Before invoking `gh issue create`, provision the `epic:<slug>` label using the slug approved in step 3:

1. Check whether the label already exists: `gh label list --search "epic:<slug>" --json name --jq '.[] | select(.name == "epic:<slug>") | .name'`.
2. **If missing**, create it with a shared color and description:
   ```bash
   gh label create "epic:<slug>" \
     --color 5319e7 \
     --description "Belongs to epic: <epic title>"
   ```
   The color `#5319e7` (purple family) is shared across all `epic:<slug>` labels so they're visually grouped in the GitHub UI.
3. **If already present**, do not silently reuse it. Warn the user via `AskUserQuestion` — for example: "Label `epic:<slug>` already exists in this repo. Reuse it for this epic?" with options `Reuse existing label`, `Pick a different slug`, and `Cancel`. Only proceed with the existing label after the user selects `Reuse existing label`. If the user picks a different slug, loop back to step 3 to edit the plan's `Epic label:` line, then re-check.

Then pass all three labels to `gh issue create`:

```bash
gh issue create \
  --title "epic: <short description>" \
  --label "epic" \
  --label "epic:<slug>" \
  --label "priority:<level>" \
  --body "<epic body>"
```

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

- After presenting a plan or draft, always request approval via the `AskUserQuestion` tool — not prose. A silent wait with no tool call (or a prose-only "let me know what you think") is a defect.
- Never create issues without showing the plan and getting approval first
- Never write plan files to disk — the plan lives in the conversation only
- Only create an epic if there are 2 or more child issues — skip step 5 entirely for single-issue plans
- Epic issue must be created last, after all child issue numbers are known
- If `$ARGUMENTS` is empty, ask what to spec before doing anything else
- Never invoke `speckit:interview` directly in response to a user typing `/spec` or triggering this skill. `speckit:interview` is a sub-skill called from within step 2 of this skill — it is never a substitute for `speckit:spec`. If you find yourself about to invoke `speckit:interview` as a top-level response to `/spec`, stop and invoke `speckit:spec` instead.
