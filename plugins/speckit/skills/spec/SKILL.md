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

> **Path gate**: run step 2a first. It classifies the request and may
> short-circuit the skill. Only run this step when step 2a selects
> `Full interview`.

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

Parse the structured sections (Goal, Background, Requirements, Out of Scope,
Tasks) from the sub-skill output. Ignore any prose that appears after the
Tasks table — it belongs to the sub-skill's standalone mode and must not
influence the orchestrator's next action. The orchestrator owns the handoff
from here: step 3 is the only approval gate.

Do not proceed to step 3 until `/speckit:interview` has produced a complete,
unambiguous output with all five sections present.

### 2a. Classify simple vs. full path

**Execution order**: this step runs BEFORE step 2. Numbered 2a to keep later
step numbers stable, but it is the first gate after step 1. The simple path
exists to keep trivial changes from being inflated into multi-task epics.

Using the codebase scan from step 1 and the shape of `$ARGUMENTS`, classify
the request as **simple** or **full**.

**Simple-path heuristic** — a request qualifies as simple only if BOTH hold:

- **Single conceptual change** — one cohesive behaviour, fix, or tweak. Not a
  bundle of independent changes hiding behind a shared theme.
- **Single file, or tightly co-located files in one skill/module directory** —
  the work touches one file, or a small number of files inside one
  skill/module directory (e.g. `plugins/foo/skills/bar/*`).

If either test fails (multiple conceptual changes, or changes spanning unrelated
modules), the request is a full-path request.

**Classification handling** — do not prompt the user up front when the
heuristic is confident. The routing decision is narrated inline for
clearly-simple and clearly-full inputs; an `AskUserQuestion` call fires only
when the heuristic is ambiguous. The final plan-approval gate in step 3 is the
user's primary escape hatch (including re-scope between simple and full).

Map every input to exactly one of the three cases below:

- **Clearly simple** — both heuristic tests pass unambiguously: the request
  describes one cohesive change AND the codebase scan points at a single file
  (or clearly co-located files in one skill/module directory). Narrate the
  classification inline in one sentence (e.g. "This looks like a single-file,
  single-concept change — running simple path") and proceed directly to the
  inline lightweight interview under "On Simple path" below. **Do not call
  `AskUserQuestion` for routing.**
- **Clearly full** — at least one heuristic test fails unambiguously: the
  request describes multiple independent conceptual changes, OR the scan points
  at multiple files across unrelated modules. Narrate the classification inline
  (e.g. "This looks like a multi-file change — running full interview") and
  fall through to step 2 (`/speckit:interview`). **Do not call
  `AskUserQuestion` for routing.**
- **Ambiguous** — the heuristic is uncertain. Typical signals: single file but
  multiple plausibly-independent concepts that could merge or split; input
  under-specifies scope so file count is borderline; concepts read as one
  theme but the implementation could fan out across modules. In this case
  only, call `AskUserQuestion` once with options `Simple path — one issue`,
  `Full interview — epic path`, `Cancel`. State the inferred file(s) and the
  specific ambiguity in the question prose so the user can resolve it.

**On Simple path** (clearly-simple narration, or `Simple path` picked in the
ambiguous prompt) — short-circuit the rest of this skill:

1. Run one lightweight interview round **inline in this skill** — a single
   `AskUserQuestion` call with 1–3 questions covering the tightest remaining
   gaps (scope, acceptance criteria, any blocking decision). Do NOT invoke
   `speckit:interview` — keep the interview inline to preserve the short-circuit.
2. Draft a single-issue plan with Goal, Background, Requirements, Out of Scope,
   and exactly one task. Fold any documentation updates into that task's
   acceptance criteria — do NOT append the auto-documentation task from the
   full-interview flow.
3. Show the plan and call `AskUserQuestion` for approval in the same turn (same
   shape rules as step 3, using the simple-path option set).
4. On approval, hand the single task to `/catalog` with **no `--epic` flag**.
   Catalog files one standalone issue. Skip step 2.5, step 5 (no epic tracking
   issue), and the sub-issue / blocked-by wiring.
5. Jump to step 6 to report the filed issue, then stop.

**On Full interview** (clearly-full narration, or `Full interview` picked in
the ambiguous prompt): fall through to step 2 (invoke `/speckit:interview`)
unchanged. **On `Cancel`** (only reachable from the ambiguous prompt): abort
the skill.

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

**Required turn shape**: the turn that presents the plan MUST contain, in
this exact order, (a) the plan markdown and (b) exactly one `AskUserQuestion`
tool call. Any turn that emits the plan and ends without the tool call is a
defect and must be corrected by immediately emitting the `AskUserQuestion`
call. This is non-negotiable — no prose ending (silent wait, `/catalog`
hand-off suggestion, encouragement to reply, or any other text) is acceptable
in place of the tool call. The `AskUserQuestion` call is the only valid
approval gate and is the sole plan-filing approval for the skill on both
paths.

The options depend on whether the plan is a simple-path single issue or a
full-path epic. `AskUserQuestion` supports max 4 options total (including
`Cancel`); `Other` is added automatically and does not count.

- **Simple-path plan** (single issue, reached from the `On Simple path`
  short-circuit in step 2a). Question: "Approve this plan and file the issue?"
  Options: `Approve and file`, `Run full interview instead`, `Adjust`,
  `Cancel`.
  - On `Run full interview instead`: discard the single-issue draft and fall
    through to step 2 (invoke `/speckit:interview`). Do not re-ask the step 2a
    routing prompt.
  - On `Adjust`: let the user revise the plan, then re-show the plan with the
    same options in a new turn.
- **Full-path plan** (epic). Question: "Approve this plan and file the
  issues?" Options: `Approve and file issues`, `Condense to single issue`,
  `Adjust plan`, `Cancel`. Epic-label edits happen through `Adjust plan` — the
  user asks for a label change and the skill revises the `Epic label:` line
  before re-asking.
  - On `Condense to single issue`: discard the epic plan and re-run the
    simple-path drafting inline — one lightweight `AskUserQuestion` interview
    round (if needed to tighten scope), draft a single-issue plan with exactly
    one task, then re-show using the simple-path option set above.
  - On `Adjust plan`: revise the plan (priorities, tasks, or the epic label),
    then re-show with the same options.

**Wrong shape — silent wait** (never do this):

```
Here is the plan:
## Goal
Harden approval gates in speckit skills.
...
Let me know if you'd like changes.
← turn ends here; silent wait
```

**Wrong shape — `/catalog` hand-off prose** (never do this):

```
Here is the plan:
## Goal
Harden approval gates in speckit skills.
...
Plan ready to feed into `/speckit:catalog` to file as a single prioritised, labelled GitHub issue.
← turn ends here
```

This is a defect — the `/catalog` hand-off prose was inherited from the
interview sub-skill's standalone-mode wording and must not be propagated. The
orchestrator owns the handoff and the only legitimate way to end this turn is
with an `AskUserQuestion` call.

**Right shape — full-path plan** (always do this):

```
Here is the plan:
## Goal
Harden approval gates in speckit skills.
...
← immediately followed by AskUserQuestion in the same turn:
AskUserQuestion("Approve this plan and file the issues?", [
  "Approve and file issues",
  "Condense to single issue",
  "Adjust plan",
  "Cancel"
])
```

**Right shape — simple-path plan**:

```
AskUserQuestion("Approve this plan and file the issue?", [
  "Approve and file",
  "Run full interview instead",
  "Adjust",
  "Cancel"
])
```

Do not proceed to step 4 until the user has answered via `AskUserQuestion`. If the user selects an adjust, re-scope, or cancel option, loop back (revise the plan, fall through to the other path, or abort) before re-asking.

The slug the user approves in this step is the single source of truth for the epic label and must be used verbatim in step 4 (catalog handoff for children) and step 5 (epic tracking issue).

### 4. File child issues

Pass the full task list from the plan to `/catalog` in a single call, prefixing the arguments with `--epic <slug>` so catalog associates the filed issues with the approved epic. Use the public `--epic <slug>` token that catalog documents in its input contract — do not use a private side channel. `/catalog` handles duplicate detection, label creation, and issue body format.

Do not instruct `/catalog` to embed `Depends on #N` lines (or any other `#<number>` task-reference) in issue bodies. GitHub auto-links `#N` tokens, so a body that says "Depends on task #3" will link to unrelated issue 3 in the repo. Task-to-task dependencies are wired in step 5 via the native GitHub blocked-by API — keep them out of the issue body.

**After `/catalog` returns, do not pause and do not wait for user input. Proceed immediately to step 5.** The catalog sub-skill's final output is the results table; any trailing prose it may emit is noise and must be ignored. The orchestrator owns the transition and must advance autonomously.

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

- A turn that presents the plan and ends without an `AskUserQuestion` call is a defect — whether the ending prose is silent waiting, a `/catalog` hand-off suggestion, or any other text.
- The plan and the `AskUserQuestion` approval call must be emitted in the **same assistant turn** — presenting the plan and ending the turn without calling `AskUserQuestion` is a defect, even if a prose invitation is included.
- Never create issues without showing the plan and getting approval first
- Never write plan files to disk — the plan lives in the conversation only
- Only create an epic if there are 2 or more child issues — skip step 5 entirely for single-issue plans
- Epic issue must be created last, after all child issue numbers are known
- If `$ARGUMENTS` is empty, ask what to spec before doing anything else
- Never invoke `speckit:interview` directly in response to a user typing `/spec` or triggering this skill. `speckit:interview` is a sub-skill called from within step 2 of this skill — it is never a substitute for `speckit:spec`. If you find yourself about to invoke `speckit:interview` as a top-level response to `/spec`, stop and invoke `speckit:spec` instead.
