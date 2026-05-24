---
name: agent-team-retro
description: Run a retrospective on the currently-spawned squad. Polls each active member with three fixed questions, aggregates findings into severity-grouped action items, applies approved edits to role contracts (project-local override preferred), and optionally hands findings off to speckit:catalog as GitHub issues.
triggers:
  - "/agent-team-retro"
  - "run a retro"
  - "team retro"
  - "squad retro"
  - "role contract retro"
allowed-tools: SendMessage, AskUserQuestion, Read, Edit, Write, Bash, Skill
---

# Agent Team Retro

Evolve squad role contracts from real-session learnings. This skill polls each currently-spawned team member with three fixed questions, synthesizes the responses into action items grouped by severity, and applies approved edits to the role contract files. Findings the user does not want applied as edits can optionally be filed as GitHub issues via `speckit:catalog`.

The retro is **session-scoped** — it operates only on members currently spawned in the active team config, never on idle or historical rosters.

## Process

### Phase 1 — Discovery

Locate the active team config under `~/.claude/teams/`. Each squad writes a `config.json` there at spawn time; the file lists the roster, lead session, and per-member metadata.

```bash
ls ~/.claude/teams/*/config.json 2>/dev/null
```

Resolve which team this retro targets. Note: the session running this retro is the **orchestrator**, which IS the team-lead under squadkit's orchestrator-is-lead model — it has no addressable `members[]` entry of its own. Match by member `cwd` (the orchestrator's `$PWD` matches the repo root recorded in `squadkit.json` for one and only one team) or by current session id appearing in any historical handoff record.

1. **Single config present** — use it.
2. **Multiple configs present** — prefer the one whose sibling `squadkit.json` records a `repo_root` equal to the orchestrator's main-repo root, or whose any-member `cwd` equals `$PWD`. If still ambiguous, present the candidates via `AskUserQuestion` and let the user pick.
3. **No configs present** — graceful no-op:

   > No active squad — skipping retro. Spawn a team first (`/spawn-team`) to run a retro against it.

   Exit cleanly. Do not error.

Read the resolved `config.json` and extract:

- `name` — team name.
- `members[]` — array of `{name, agentType, agentFile, cwd, sessionId}`. Filter to members that are **currently spawned** (have a live `sessionId` recorded). Skip any member whose `sessionId` is null, empty, or marked terminated.

If the filtered roster is empty after this step, treat it as a solo session and emit the same graceful no-op message above.

### Phase 2 — Poll

Send each currently-spawned member the **same three fixed questions** via `SendMessage`. Each response is capped at **200 words**.

The three questions (verbatim, in this order):

1. *What worked well in your role this session?*
2. *What friction or blockers did you hit (coordination, contract gaps, ambiguous protocols)?*
3. *What ONE concrete change to your role contract would have helped most?*

For each member, include this preamble in the `SendMessage` payload:

> Reply to this poll **via SendMessage** (not as plain assistant output) with text answers to each of the three questions below. Each answer max **200 words**. Be specific — name the protocol, file, or contract clause you mean. If you have nothing for a question, say "nothing notable" rather than padding. Going idle without a SendMessage reply will be treated as a missed response and re-pinged.

After receiving each response, count words per answer. If any answer exceeds 200 words, send a single follow-up `SendMessage` asking the member to compress that answer to 200 words or fewer, then use the compressed version. Do not silently truncate.

Polls run **in parallel** across members — fire all `SendMessage` calls in a single batch and collect the replies before moving on.

#### Ack discipline

After firing all polls, **wait for SendMessage replies (not idle notifications) from all N members** before proceeding to Phase 3. Treat an idle notification with no accompanying SendMessage payload as a **missed response**, not a completion signal — the member processed the prompt but failed to route their answer through the SendMessage channel.

If any member emits an idle without a substantive SendMessage reply within **60 seconds** of the initial poll, send **one re-ping per such member** with this exact framing:

> My retro prompt registered as idle — please reply via SendMessage.

Wait again for SendMessage replies from the re-pinged members. Only after every polled member has returned a SendMessage reply (or the operator explicitly waives a non-responder via `AskUserQuestion`) may Phase 3 begin. Do not aggregate against a partial roster silently.

### Phase 3 — Aggregate

Synthesize the per-member responses into a flat list of **action items**. Each action item targets a specific role contract file (or a cross-cutting protocol).

Group action items by **severity**:

| Severity | Definition |
|----------|------------|
| **high** | Raised by 2+ members, OR blocks a core protocol (handoff, spawn, review gate) |
| **medium** | Role-specific friction raised by one member, with a concrete proposed fix |
| **low** | Nice-to-have, polish, or stylistic refinement |

Each action item should record:

- `id` — short slug (e.g. `builder-add-rebase-clause`)
- `severity` — `high` / `medium` / `low`
- `targetRole` — which role's contract this edits (`team-lead`, `architect`, `builder`, `reviewer`, `tester`, `explorer`, `designer`, or `cross-cutting`)
- `summary` — one-sentence description of the change
- `rationale` — which member(s) raised it and why

### Phase 4 — Approve

Present action items to the user via `AskUserQuestion`. Use **one question per non-empty severity bucket**, multi-select, so the user can cherry-pick within each tier:

- Question 1: *Which **high**-severity items should be applied to role contracts?* (multi-select; option per item with summary + targetRole)
- Question 2: *Which **medium**-severity items should be applied?* (multi-select)
- Question 3: *Which **low**-severity items should be applied?* (multi-select)

Skip any bucket that is empty. Record the approved set; everything not selected is a candidate for Phase 6 catalog handoff.

### Phase 5 — Apply edits

For each approved action item, locate the target role contract file using this resolution order:

1. **Project-local override** — `.claude/agents/<targetRole>.md` (preferred — this is the user's customization layer; editing here keeps changes local without forking the plugin).
2. **Bundled** — `plugins/squadkit/agents/<targetRole>.md`.

Resolution rules:

- **Project-local exists** → edit it directly via `Edit`.
- **Only bundled exists** → ask the user, via `AskUserQuestion`, whether to:
  - (a) edit the bundle directly (changes the plugin in-place), or
  - (b) copy the bundle to `.claude/agents/<targetRole>.md` and edit the copy (preserves the bundle, creates a project-local override).

  Default recommendation: (b) — keeps the user's customizations isolated from upstream plugin updates.
- **Neither exists** → skip the item and log a warning in the final summary.

For `cross-cutting` items, ask the user which role(s) the edit should land in (or whether to defer the item to Phase 6).

Apply each edit via the `Edit` tool. Make the change minimal and surgical — only the clause being added, refined, or removed, never a full rewrite.

### Phase 6 — Catalog handoff (opt-in)

After edits are applied, ask the user:

> Any unapplied findings worth filing as GitHub issues? (yes/no)

If **yes**: invoke `speckit:catalog` with the unapplied findings as input. Pass the action items (id, severity, targetRole, summary, rationale) so catalog can convert them into properly labeled issues.

```
Skill({skill: "speckit:catalog", args: "<serialized findings>"})
```

If **no**: proceed to Phase 7 (teardown).

### Phase 7 — Teardown

Before invoking `TeamDelete` to retire the team registry, perform a **worktree-cleanup pass** so per-member git worktrees are removed alongside the registry — leaving them on disk causes stale-worktree silent reuse on subsequent spawns (see #631).

1. **Resolve the team's recorded worktrees.** Read both metadata files for the team resolved in Phase 1:

   - `~/.claude/teams/${TEAM_NAME}/config.json` — canonical roster; each `members[]` entry records a `cwd` field.
   - `~/.claude/teams/${TEAM_NAME}/squadkit.json` — orchestrator-is-lead metadata sidecar (may also carry per-member worktree paths).

   Collect every `.claude/worktrees/<member>/` path referenced across both files. De-duplicate. Skip the orchestrator's own `cwd` (the orchestrator runs out of the main repo root, not a `.claude/worktrees/` path) — never `git worktree remove` your own working directory.

2. **Remove each worktree.** For every collected path, run:

   ```bash
   git worktree remove --force <path>
   ```

   Use `--force` because builders may have left uncommitted scratch state behind; the team is being torn down, so that state is intentionally discarded. If a path does not exist (already cleaned, never created, or moved), record it as **skipped** and continue — do not error.

3. **Log the result.** Emit a short summary of:

   - Paths cleaned (one line each).
   - Paths skipped, with the reason (e.g. `path missing`, `not a registered worktree`, `already removed`).

4. **Then** invoke `TeamDelete` to remove the `~/.claude/teams/${TEAM_NAME}/` registry. The cleanup pass runs **before** `TeamDelete` so that the metadata files are still readable when collecting paths in step 1.

Exit cleanly with a final summary that includes both the edits applied (Phase 5), the catalog handoff result (Phase 6), and the worktree-cleanup log.

## Output

Final report includes:

- Team name and roster size polled
- Action items applied (per role, per severity)
- Action items skipped (with reasons)
- Whether catalog handoff ran, and how many issues were filed
- Worktrees cleaned and worktrees skipped during teardown (with reasons)
