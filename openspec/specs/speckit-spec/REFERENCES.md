# speckit-spec — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `sop/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Codebase Context Exploration

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:25-29` — Step 1: grep/glob for files relevant to `$ARGUMENTS`; run in background while forming first question batch; collect before writing plan in step 3.

### Scenario: Relevant files fetched before plan is written
**Source:** `plugins/speckit/skills/spec/SKILL.md:25-29` — "Run this in the background while forming the first question batch; do not wait for it. Collect results before writing the plan in step 3."
**Interpolated; no direct test.**

---

## Requirement: Simple vs. Full Path Classification

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:62-130` — Step 2a: heuristic definition, three cases (clearly simple, clearly full, ambiguous), simple-path short-circuit steps.
- `plugins/speckit/skills/spec/SKILL.md:68-75` — Simple-path heuristic: single cohesive change AND single file/co-located files.
- `plugins/speckit/skills/spec/SKILL.md:78-84` — Classification handling: narrate inline when confident, `AskUserQuestion` only when ambiguous.
- `plugins/speckit/skills/spec/SKILL.md:108-125` — Simple-path execution: inline interview, single-issue plan, catalog without `--epic`.

### Scenario: Clearly simple path narrated and short-circuited
**Source:** `plugins/speckit/skills/spec/SKILL.md:86-92` — "Narrate the classification inline in one sentence … and proceed directly to the inline lightweight interview."
**Interpolated; no direct test.**

### Scenario: Clearly full path narrated and falls through to interview
**Source:** `plugins/speckit/skills/spec/SKILL.md:93-99` — "Narrate the classification inline … and fall through to step 2."
**Interpolated; no direct test.**

### Scenario: Ambiguous path asks user once
**Source:** `plugins/speckit/skills/spec/SKILL.md:100-107` — "call `AskUserQuestion` once with options `Simple path — one issue`, `Full interview — epic path`, `Cancel`."
**Interpolated; no direct test.**

### Scenario: Simple path files one issue without epic
**Source:** `plugins/speckit/skills/spec/SKILL.md:108-125` — "hand the single task to `/catalog` with no `--epic` flag … Skip step 2.5, step 5 (no epic tracking issue), and the sub-issue / blocked-by wiring."
**Interpolated; no direct test.**

---

## Requirement: Epic Slug Derivation

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:132-150` — Step 2.5: slug derivation rules (lowercase, kebab-case, strip fillers, cap 30 chars), editable during plan approval.

### Scenario: Slug derived from epic title
**Source:** `plugins/speckit/skills/spec/SKILL.md:137-143` — derivation rules with example.
**Interpolated; no direct test.**

### Scenario: Slug omitted for single-issue plans
**Source:** `plugins/speckit/skills/spec/SKILL.md:133-134` — "Only run this step if the plan will produce an epic — i.e. there are 2 or more tasks."
**Interpolated; no direct test.**

---

## Requirement: Plan Approval Gate

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:152-274` — Step 3: plan sections, turn shape requirements, wrong/right shape examples, option sets for simple and full paths.
- `plugins/speckit/skills/spec/SKILL.md:185-193` — "Required turn shape: the turn that presents the plan MUST contain, in this exact order, (a) the plan markdown and (b) exactly one `AskUserQuestion` tool call."
- `plugins/speckit/skills/spec/SKILL.md:277-291` — TaskCreate block on full-path approval.

### Scenario: Full-path plan and approval call in same turn
**Source:** `plugins/speckit/skills/spec/SKILL.md:247-261` — right shape example with four options.
**Interpolated; no direct test.**

### Scenario: Simple-path plan and approval call in same turn
**Source:** `plugins/speckit/skills/spec/SKILL.md:263-268` — right shape for simple path with four options.
**Interpolated; no direct test.**

### Scenario: Task tracking created on full-path approval
**Source:** `plugins/speckit/skills/spec/SKILL.md:277-291` — `TaskCreate` called immediately after approval with five tasks: file-children, create-epic-tracking-issue, wire-sub-issues, wire-blocked-by-edges, final-report.
**Interpolated; no direct test.**

---

## Requirement: Child Issue Filing

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:293-317` — Step 4 and Continuation Gate: invoke `/catalog` with `--epic <slug>`, advance immediately after it returns.
- `plugins/speckit/skills/spec/SKILL.md:304-316` — Continuation Gate explicitly prohibits pausing after `/catalog` returns.

### Scenario: Catalog invoked with epic flag
**Source:** `plugins/speckit/skills/spec/SKILL.md:296-299` — "Pass the full task list from the plan to `/catalog` in a single call, prefixing the arguments with `--epic <slug>`."
**Interpolated; no direct test.**

### Scenario: Orchestrator advances after catalog returns
**Source:** `plugins/speckit/skills/spec/SKILL.md:304-307` — "After `/catalog` returns, do not pause and do not wait for user input. Proceed immediately to step 5."
**Interpolated; no direct test.**

---

## Requirement: Epic Tracking Issue Creation

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:319-386` — Step 5: epic creation, label provisioning, sub-issue wiring, blocked-by wiring.
- `plugins/speckit/skills/spec/SKILL.md:343-370` — Epic label provisioning: check, create if missing, confirm if existing.
- `plugins/speckit/skills/spec/SKILL.md:372-384` — Sub-issue wiring via GitHub API using numeric `id`.

### Scenario: Epic issue created after all children
**Source:** `plugins/speckit/skills/spec/SKILL.md:326-342` — epic body shape, title format `epic: <description>`, three required labels.
**Interpolated; no direct test.**

### Scenario: Epic label provisioned before creation
**Source:** `plugins/speckit/skills/spec/SKILL.md:347-355` — `gh label create` with color `5319e7` when label is missing.
**Interpolated; no direct test.**

### Scenario: Existing epic label requires confirmation
**Source:** `plugins/speckit/skills/spec/SKILL.md:356-361` — `AskUserQuestion` with options Reuse/Pick different slug/Cancel.
**Interpolated; no direct test.**

### Scenario: Children attached as sub-issues
**Source:** `plugins/speckit/skills/spec/SKILL.md:372-379` — `gh api repos/{owner}/{repo}/issues/{epic_number}/sub_issues` POST with numeric `id` (not issue number).
**Interpolated; no direct test.**

---

## Requirement: Blocked-By Edge Wiring

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:380-386` — Step 5 blocked-by wiring: GitHub blocked-by API call for each task with a Depends On value.

### Scenario: Blocked-by edges wired for dependent tasks
**Source:** `plugins/speckit/skills/spec/SKILL.md:380-385` — `gh api repos/{owner}/{repo}/issues/{blocked_number}/dependencies/blocked_by` POST with `-F issue_id`.
**Interpolated; no direct test.**

### Scenario: No-dependency plan skips wiring
**Source:** `plugins/speckit/skills/spec/SKILL.md:386` — "Close with `TaskUpdate(wire-blocked-by-edges, status: 'completed')` once every edge is set (or immediately, if the plan declares no `Depends On` edges)."
**Interpolated; no direct test.**

---

## Requirement: Team-Readiness Assessment

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:388-474` — Step 6: four suitability signals, three-signal threshold, phase label provisioning, phase assignment, dispatch comment shape.
- `plugins/speckit/skills/spec/SKILL.md:398-409` — Four suitability signals enumerated.
- `plugins/speckit/skills/spec/SKILL.md:411-415` — Skip line when fewer than three signals hold.

### Scenario: Team-suitable spec gets phase labels and dispatch comment
**Source:** `plugins/speckit/skills/spec/SKILL.md:417-473` — provision phase labels, assign issues to phases, post dispatch summary comment on epic.
**Interpolated; no direct test.**

### Scenario: Non-team-suitable spec prints skip line
**Source:** `plugins/speckit/skills/spec/SKILL.md:411-415` — "print a single line and stop" when fewer than three signals hold.
**Interpolated; no direct test.**

---

## Requirement: Pre-End Self-Check

**Sources**
- `plugins/speckit/skills/spec/SKILL.md:500-507` — Pre-end self-check section: `TaskList` as turn-end gate, worked failure-mode example.
- `plugins/speckit/skills/spec/SKILL.md:303-316` — Continuation Gate (companion rule for the `/catalog` boundary specifically).

### Scenario: Pending tasks prevent turn end
**Source:** `plugins/speckit/skills/spec/SKILL.md:500-505` — "If any spec task is `pending` or `in_progress`, do not end the turn — execute the next task."
**Interpolated; no direct test.**

### Scenario: All tasks completed allows turn end
**Source:** `plugins/speckit/skills/spec/SKILL.md:500` — implied: turn-end is legitimate only when all tasks are completed or the user has explicitly halted.
**Interpolated from absence.**

---

## Cross-cutting interpretive notes

1. **All scenarios interpolated from absence of tests** — speckit/spec has no automated test suite. All behavioral claims are derived from reading the SKILL.md prose.

2. **Two-gate continuation model** — The skill has two overlapping continuation guards: the Continuation Gate (lines 303-316, specific to the `/catalog` boundary) and the Pre-end Self-Check (lines 500-507, the orchestrator-wide gate). Both are intentionally separate; the skill comment at line 503 explains why.

3. **Simple path skips five steps** — The simple path short-circuit (step 2a) skips slug derivation (step 2.5), epic creation (step 5), sub-issue wiring, blocked-by wiring, and team assessment (step 6). These skips are all documented in lines 108-125 but only implied elsewhere.

4. **Team dispatch comment is a comment, not an issue** — Line 455 specifies `gh issue comment` (not `gh issue create`). This is a non-obvious detail that distinguishes the dispatch summary from the child issues filed in step 4.

5. **Sub-issue API uses numeric id, not issue number** — Line 377 notes "Use the numeric `id` (not the issue number) — fetch it from `gh issue view {number} --json id`." This is a GitHub API quirk and the most common source of failure in this step.
