---
name: catalog
description: Convert code review findings or assessment results into prioritized, labeled GitHub issues. Supports explicit input, conversation context, or file paths.
---

# Catalog Skill

Convert findings into prioritized, labeled GitHub issues: $ARGUMENTS

## Input

Accept findings from any of these sources (check in order):

1. **Explicit input** in `$ARGUMENTS` (e.g., a pasted list, a file path)
2. **Earlier in this conversation** — look for structured findings from code review or any assessment that produced categorized results
3. **A file** — if `$ARGUMENTS` is a path, read it and extract findings

If no findings are available, ask the user what to catalog.

### Tokens in `$ARGUMENTS`

Before extracting findings, scan `$ARGUMENTS` for these optional leading tokens and strip them from the findings text:

- `--auto` — skip the approval step in step 3 (see below).
- `--epic <slug>` — associate the catalogued issues with an epic. Ensures `epic:<slug>` label exists (step 2) and applies it to every issue in the batch (step 4). An optional epic title may accompany the slug; it is used as the label description when creating the label.
- `--split` — disable the consolidation heuristic (see step 1.5 below) and file one issue per row of the source blueprint table. Use this when the rows of a phase really are independent units of work that need separate issues, branches, or owners. Without `--split`, mechanically-related rows in the same phase fold into a single issue per phase (the default).

If `--epic <slug>` is **not** present, behaviour is unchanged from the no-epic flow: no epic label is applied, no warning is emitted, and the rest of the process runs exactly as documented below.

## Process

### 1. Extract findings

Parse the source into discrete findings. Each finding needs:
- **Title**: short, specific (under 70 characters)
- **Category**: bug, enhancement, refactor, documentation, hygiene
- **Severity**: high (breaks things, misleads users), medium (degrades quality), low (style, nice-to-have)
- **Body**: Problem statement, why it matters, suggested fix

When the source is a blueprint with a multi-row "Child issue list" table (or any equivalent phase-grouped row breakdown), the row count is **not** the issue count. Each row is a candidate finding; apply the heuristic in step 1.5 to decide which rows fold together before counting issues.

### 1.5. Consolidate phase-mate findings

If the extracted findings carry phase labels (e.g. `phase:1`, `phase:2`) or were sourced from a blueprint table that groups rows by phase, run a consolidation pass before presenting the catalog. The default behaviour collapses mechanically-related rows in the same phase into a single issue; use `--split` to disable this and file one issue per row.

**Default rule**: rows in the same phase consolidate into one issue when **both** of the following hold:

- **Shared scope** — the rows describe instances of the same mechanical work (e.g. "port shadcn primitive Button", "port shadcn primitive Input", "port shadcn primitive Select" — all the same kind of change against sibling targets), share acceptance criteria, or have near-identical body templates.
- **No inter-dependency** — no row lists another row in the same phase as a prerequisite, blocker, or strict-ordering dependency. If row B says "after A is merged" or "depends on A", A and B stay split.

Rows that fail either check stay as their own issue. A phase may end up with a mix — e.g. four shadcn primitive ports fold into one issue, while a settings card port in the same phase stays separate because it has different acceptance criteria.

When consolidating, the resulting issue's body lists each folded row as a checklist item under `## Suggested fix`, preserving the row text verbatim. The title summarises the group (e.g. "Phase 2: port shadcn primitives — Button, Input, Select, Switch") rather than naming a single row.

If `--split` is in `$ARGUMENTS`, skip this entire step — every extracted row becomes its own issue (the legacy behaviour).

### 1.6. Print pre-file consolidation summary

Before moving on to step 2, emit a one-line summary per phase showing the consolidation outcome, so the user can redirect with `--split` if the default folding is wrong. Example:

```
Consolidation summary:
- Phase 1 (contracts): 2 rows → 2 issues (no consolidation; rows have distinct scope)
- Phase 2 (UI ports): 5 rows → 2 issues (4 shadcn primitive ports consolidated; 1 settings card kept separate)
- Phase 3 (integration): 3 rows → 1 issue (all rows share scope and have no inter-dependency)
```

If `--split` was passed, print a single line instead:

```
Consolidation summary: --split active; filing 1 issue per row (10 rows → 10 issues).
```

This summary is informational — it precedes the catalog table in step 3 and does not require its own approval gate (the step 3 `AskUserQuestion` covers the whole batch). When `--auto` is also active, the summary still prints so the run record shows the decision.

### 2. Check existing labels

```bash
gh label list --repo <repo> --limit 50
```

Create any missing labels needed for the findings:
- Category labels if not present
- `priority:high`, `priority:medium`, `priority:low` if not present

Only create labels that will actually be used by the current findings.

**If an epic slug was supplied via `--epic <slug>`**, also ensure the `epic:<slug>` label exists:

- If the label is **missing**, create it with the shared epic styling:
  ```bash
  gh label create "epic:<slug>" \
    --repo <repo> \
    --color 5319E7 \
    --description "Belongs to epic: <epic title>"
  ```
  If no epic title was passed alongside the slug, fall back to a description of `Belongs to epic: <slug>`.
- If the label **already exists**, warn the user once for this batch and ask before reusing it:
  ```
  WARNING: label `epic:<slug>` already exists in this repo. Reusing it will
  apply it to every issue filed in this batch. Proceed? (y/N)
  ```
  Only continue after explicit approval. Do not silently reuse. This prompt fires at most once per catalog invocation.

If no epic slug was supplied, skip this entire block — do not list, create, or prompt for any `epic:*` label.

### 3. Present the catalog for approval

Show the user a summary table before creating anything. The `Labels` column must list every label that will be applied at creation time — including `epic:<slug>` when an epic slug is in play — so the user can confirm the full set before anything is filed:

```
| # | Title | Category | Priority | Labels |
|---|-------|----------|----------|--------|
| 1 | ...   | bug      | high     | bug, priority:high |
| 2 | ...   | refactor | medium   | refactor, priority:medium |
```

When an epic slug was supplied, the table also shows the epic label on every row and includes a single header line above the table making it explicit, e.g.:

```
Epic: epic:<slug> (applied to every issue below)

| # | Title | Category | Priority | Labels |
|---|-------|----------|----------|--------|
| 1 | ...   | bug      | high     | bug, priority:high, epic:<slug> |
| 2 | ...   | refactor | medium   | refactor, priority:medium, epic:<slug> |
```

If `--auto` was passed in `$ARGUMENTS`, skip the approval step and proceed directly to issue creation.

Otherwise, **in a single assistant turn**, emit (a) the catalog table above and (b) an `AskUserQuestion` call. Never end the turn after presenting the table without the tool call — a prose-only prompt like "let me know if you'd like changes" is a defect.

**Pre-end self-check**: Before ending the turn in step 3, verify that the last action is an `AskUserQuestion` call. If the table was shown but no tool call was made, emit the call immediately.

The user may ask to:
- Remove findings they don't want filed
- Adjust priorities
- Change titles or descriptions
- Add additional context

If adjustments are requested, update the table and re-present with a new `AskUserQuestion` in the same turn.

### 4. Create issues

After approval, create all issues via `gh issue create`:
- Apply the labels from the table — every issue gets its category label and priority label
- **If an epic slug was supplied via `--epic <slug>`**, also pass `--label "epic:<slug>"` on every `gh issue create` invocation in the batch, alongside the category and priority labels. No issue in the batch may be created without the epic label when a slug is in play.
- If no epic slug was supplied, do not pass any `epic:*` label.
- Structure the body with:
  - `## Problem` — what's wrong
  - `## Why this matters` — impact and severity rationale
  - `## Suggested fix` — concrete next steps
- Create issues **sequentially** (one at a time) in priority order (high first).
  Never parallelize `gh issue create` calls — parallel bash invocations return
  URLs in completion order, not invocation order, which silently scrambles the
  title↔number mapping. Capture each URL immediately after creation and pair
  it with the exact title just filed.

### 4.5. Verify the title↔number mapping

Before reporting the results in Step 5, verify each created issue's title
matches the title you intended:

```bash
printf '%s\n' <N1> <N2> ... | while read N; do
  gh issue view "$N" --json title --jq '.title'
done
```

Assert each returned title matches the corresponding row in your catalog
table. If any mismatch, halt and report — do not pass unverified numbers
to downstream steps (e.g., /swarm, /x-squad, /ship) where Closes-ref accuracy
depends on the mapping.

### 5. Report

Output the created issues as a table with links:

```
| # | Issue | Priority | Labels |
|---|-------|----------|--------|
| 1 | [#N](url) title | high | ... |
```

**Sub-skill output contract**: When `--epic <slug>` is present (i.e. catalog was invoked from `/spec`), emit the handoff block (see [Handoff Contract](#handoff-contract)) immediately after the results table, then stop. The handoff block is the FINAL output — zero trailing prose after the closing fence, no hand-off sentence, no "returning to /spec" message, no transition language of any kind. The orchestrator resumes automatically; any trailing text will stall it. When `--epic` is NOT set, the results table remains the final output with no handoff block.

## Handoff Contract

When `/catalog` is invoked with `--epic <slug>`, it appends a final fenced block to its output immediately after the issue table in Step 5. The block uses the custom info string `spec-handoff` so orchestrators can locate it unambiguously:

````
```spec-handoff
{
  "filed": [602, 603, 604],
  "epic_slug": "squadkit-team-plugin",
  "next_phase": "create-epic-tracking-issue"
}
```
````

### Schema

| Field | Type | Description |
|-------|------|-------------|
| `filed` | integer array | Issue numbers in the order they were created (sequential, matching the issue table). |
| `epic_slug` | string | The `--epic` slug passed by the orchestrator — verbatim, no transformation. |
| `next_phase` | string | Always the literal `"create-epic-tracking-issue"`. |

### Placement rule

The block is the final element of the catalog's output, AFTER the issue table. Nothing follows the closing ` ``` ` fence.

## Constraints

- Never write `#<number>` tokens in issue bodies unless you intend a real cross-reference to that exact issue — GitHub auto-links them, so a token like `#3` in a body about "task 3" will link to unrelated issue 3 in the repo. When referring to sibling tasks from a plan, use "task 3" (no hash) or omit the reference entirely — task-to-task dependencies are wired by the caller (e.g. `/spec`) via the native GitHub blocked-by API, not via issue-body text.
