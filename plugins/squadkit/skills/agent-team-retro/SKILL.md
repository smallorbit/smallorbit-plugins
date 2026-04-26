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

Resolve which team this retro targets:

1. **Single config present** — use it.
2. **Multiple configs present** — prefer the one whose `leadSessionId` matches the current session ID, or whose any-member `cwd` equals `$PWD`. If still ambiguous, present the candidates via `AskUserQuestion` and let the user pick.
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

> Respond to each of the three questions below in **at most 200 words per answer**. Be specific — name the protocol, file, or contract clause you mean. If you have nothing for a question, say "nothing notable" rather than padding.

After receiving each response, count words per answer. If any answer exceeds 200 words, send a single follow-up `SendMessage` asking the member to compress that answer to 200 words or fewer, then use the compressed version. Do not silently truncate.

Polls run **in parallel** across members — fire all `SendMessage` calls in a single batch and collect the replies before moving on.

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

If **no**: exit cleanly with a summary of what was applied.

## Output

Final report includes:

- Team name and roster size polled
- Action items applied (per role, per severity)
- Action items skipped (with reasons)
- Whether catalog handoff ran, and how many issues were filed

## Constraints

- Poll only currently-spawned members — never historical or idle rosters
- 200-word cap per answer is enforced; compress over-limit answers via follow-up `SendMessage`, do not silently truncate
- Severity buckets in `AskUserQuestion` are presented as separate questions so the user can cherry-pick per tier
- Project-local `.claude/agents/<role>.md` always wins over bundled `plugins/squadkit/agents/<role>.md`
- Bundled-only edits require explicit user consent; default recommendation is to copy to project-local first
- Solo sessions (no team config, or no spawned members) exit cleanly with a no-op message — never error
- Catalog handoff is opt-in; never silently file issues
