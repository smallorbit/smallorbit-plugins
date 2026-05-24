# squadkit-agent-team-retro — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `<repo-root>/`.
Line numbers verified on 2026-05-24.

---

## Requirement: Active Team Discovery

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:21-37` — Phase 1 "Discovery" walks through locating `~/.claude/teams/*/config.json`, the orchestrator-is-lead resolution, and the three-way single/multi/none branch.

### Scenario: Single team config
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:31` — "**Single config present** — use it."
**Interpolated; no direct test.**

### Scenario: Repo-root match disambiguates
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:32` — "prefer the one whose sibling `squadkit.json` records a `repo_root` equal to the orchestrator's main-repo root".
**Interpolated; no direct test.**

### Scenario: Ambiguous teams prompt operator
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:32` — "If still ambiguous, present the candidates via `AskUserQuestion` and let the user pick."
**Interpolated; no direct test.**

### Scenario: No team config exits cleanly
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:33-37` — `No active squad — skipping retro` graceful no-op; line 184 constraint "Solo sessions ... exit cleanly with a no-op message — never error".
**Interpolated; no direct test.**

---

## Requirement: Spawned Member Filter

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:39-44` — extraction of `members[]` and filter to live `sessionId`s.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:179` — constraint "Poll only currently-spawned members — never historical or idle rosters".

### Scenario: Idle members excluded
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:42` — "Skip any member whose `sessionId` is null, empty, or marked terminated."
**Interpolated; no direct test.**

### Scenario: Empty filtered roster exits cleanly
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:44` — "If the filtered roster is empty after this step, treat it as a solo session and emit the same graceful no-op message above."
**Interpolated; no direct test.**

---

## Requirement: Three Fixed Questions

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:48-54` — fixed prompt set with 200-word cap.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:60` — over-limit compression directive.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:180` — constraint reinforcing the cap and the no-silent-truncation rule.

### Scenario: Question order preserved
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:50-54` — numbered list 1/2/3 (worked well / friction / one change).
**Interpolated; no direct test.**

### Scenario: Over-limit answer compressed
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:60` — "If any answer exceeds 200 words, send a single follow-up `SendMessage` asking the member to compress that answer to 200 words or fewer, then use the compressed version. Do not silently truncate."
**Interpolated; no direct test.**

---

## Requirement: Parallel Polling

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:62` — "Polls run **in parallel** across members — fire all `SendMessage` calls in a single batch and collect the replies before moving on."

### Scenario: Single batch dispatch
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:62` — same line as above.
**Interpolated; no direct test.**

---

## Requirement: SendMessage Ack Discipline

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:64-72` — Phase 2 "Ack discipline" subsection enumerating the SendMessage-vs-idle distinction, 60-second window, single re-ping, and operator waiver fallback.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:186` — constraint reiterating "idle notifications without a SendMessage payload are treated as missed responses and re-pinged once before falling back to operator confirmation".

### Scenario: Idle without reply triggers single re-ping
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:68-70` — "If any member emits an idle without a substantive SendMessage reply within **60 seconds** of the initial poll, send **one re-ping per such member** with this exact framing".
**Interpolated; no direct test.**

### Scenario: Persistent non-responder waived via operator
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:72` — "Only after every polled member has returned a SendMessage reply (or the operator explicitly waives a non-responder via `AskUserQuestion`) may Phase 3 begin."
**Interpolated; no direct test.**

---

## Requirement: Severity Buckets

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:78-84` — severity table definitions.

### Scenario: Cross-member item promoted to high
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:82` — `high` row: "Raised by 2+ members".
**Interpolated; no direct test.**

### Scenario: Protocol-blocking item promoted to high
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:82` — `high` row: "OR blocks a core protocol (handoff, spawn, review gate)".
**Interpolated; no direct test.**

---

## Requirement: Action Item Schema

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:86-92` — five-field shape (`id`, `severity`, `targetRole`, `summary`, `rationale`) with the enumerated targetRole values.

### Scenario: Item shape complete
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:88-92` — bulleted field list.
**Interpolated; no direct test.**

---

## Requirement: Per-Bucket Approval

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:94-102` — Phase 4 "Approve" with three multi-select questions per bucket and the skip-empty rule.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:181` — constraint reinforcing the per-tier cherry-pick UX.

### Scenario: Empty bucket skipped
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:102` — "Skip any bucket that is empty."
**Interpolated; no direct test.**

### Scenario: Unselected items fall through to catalog candidate set
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:102` — "everything not selected is a candidate for Phase 6 catalog handoff."
**Interpolated; no direct test.**

---

## Requirement: Project-Local Override Resolution

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:104-121` — Phase 5 "Apply edits" with the two-tier lookup, the bundled-only AskUserQuestion branch, and the cross-cutting routing.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:182-183` — constraints reinforcing project-local-wins and bundled-only consent.

### Scenario: Project-local file edited directly
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:113` — "**Project-local exists** → edit it directly via `Edit`."
**Interpolated; no direct test.**

### Scenario: Bundled-only requires consent
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:114-118` — bundled-only branch with options (a)/(b) and "Default recommendation: (b)".
**Interpolated; no direct test.**

### Scenario: Neither file present is logged and skipped
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:119` — "**Neither exists** → skip the item and log a warning in the final summary."
**Interpolated; no direct test.**

### Scenario: Cross-cutting items routed by operator
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:121` — "For `cross-cutting` items, ask the user which role(s) the edit should land in (or whether to defer the item to Phase 6)."
**Interpolated; no direct test.**

---

## Requirement: Minimal Surgical Edits

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:123` — "Apply each edit via the `Edit` tool. Make the change minimal and surgical — only the clause being added, refined, or removed, never a full rewrite."

### Scenario: Edit scope bounded
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:123` — same line.
**Interpolated; no direct test.**

---

## Requirement: Opt-In Catalog Handoff

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:125-137` — Phase 6 "Catalog handoff (opt-in)" with the yes/no branch and the `Skill({skill: "speckit:catalog", …})` invocation.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:185` — constraint "Catalog handoff is opt-in; never silently file issues".

### Scenario: Yes hands off to catalog
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:130-135` — "If **yes**: invoke `speckit:catalog` with the unapplied findings as input. Pass the action items (id, severity, targetRole, summary, rationale)".
**Interpolated; no direct test.**

### Scenario: No proceeds to teardown
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:137` — "If **no**: proceed to Phase 7 (teardown)."
**Interpolated; no direct test.**

---

## Requirement: Worktree Cleanup Before Team Delete

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:139-165` — Phase 7 "Teardown" with the four-step worktree-cleanup pass and the explicit ordering relative to `TeamDelete`.
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:187` — constraint reinforcing pre-delete cleanup and skipped-not-errored handling.

### Scenario: Both metadata files consulted
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:143-148` — step 1 collects paths from both `config.json` and `squadkit.json`, de-dupes, and excludes the orchestrator's `cwd`.
**Interpolated; no direct test.**

### Scenario: Orchestrator cwd preserved
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:148` — "Skip the orchestrator's own `cwd` ... — never `git worktree remove` your own working directory."
**Interpolated; no direct test.**

### Scenario: Missing path logged as skipped
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:156` — "If a path does not exist ... record it as **skipped** and continue — do not error."
**Interpolated; no direct test.**

### Scenario: TeamDelete runs after cleanup
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:163` — "**Then** invoke `TeamDelete` to remove the `~/.claude/teams/${TEAM_NAME}/` registry. The cleanup pass runs **before** `TeamDelete` so that the metadata files are still readable when collecting paths in step 1."
**Interpolated; no direct test.**

---

## Requirement: Final Report

**Sources**
- `plugins/squadkit/skills/agent-team-retro/SKILL.md:167-175` — "Output" section enumerates the five report elements.

### Scenario: Report content complete
**Source:** `plugins/squadkit/skills/agent-team-retro/SKILL.md:171-175` — bulleted list (team/roster, applied, skipped, catalog, worktrees).
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **No automated tests for this skill.** Behavior is documented entirely in `SKILL.md` prose. Every scenario above is interpolated from the SKILL.md directives.
2. **60-second idle window is an absolute timing constant.** It appears only on line 68 of SKILL.md and is reproduced verbatim in the spec; no other source defines it.
3. **Severity boundary is two members or protocol-blocking.** The spec mirrors line 82 exactly; no other definition of "high" exists in the codebase.
4. **Orchestrator-is-lead model is load-bearing for discovery.** The repo-root matching strategy assumes the orchestrator runs from the main repo root (not a worktree); this is recorded in line 29 of SKILL.md and line 148 reinforces it for teardown.
