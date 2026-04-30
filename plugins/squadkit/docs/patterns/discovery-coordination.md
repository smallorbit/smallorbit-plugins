# Architect-led discovery coordination

Squadkit crews come in two shapes. **Execution crews** (`kind: execution`, the default) wrap builders around an architect blueprint to produce code. **Discovery crews** (`kind: discovery`) produce blueprints — they leave a long-form GitHub issue comment per scoped problem, no code, no PRs.

The two shapes use a different coordination protocol because the deliverable is different. This document describes the discovery protocol so crews don't have to reinvent it in every custom skill.

> **Implementation note:** The `kind: discovery` profile field, the `discovery-3-role` crew profile, and the spawn-team skip logic (no worktrees, no epic-cutting, no `prBase` pinning) are implemented in companion PR #681 (closes #675 and #676). This document is item 3 of 3 in the discovery-team graduation path; #681 is items 1 and 2.

## When to use this pattern

Use a discovery crew when:

- You have a batch of GitHub issues that each need a thought-through plan before any builder picks them up.
- The plans must encode UX/contract/PII trade-offs, not just file lists.
- You want the output as durable issue comments other agents (humans, swarmkit, future squads) can consume — not as code that has to be merged.

If the work is "implement this issue", use an execution crew. If the work is "tell me how to implement this issue", use a discovery crew.

## Roles in a discovery crew

A discovery crew has three roles. Builders are absent.

| Role | Lead? | Sees mission brief? | Output |
|------|-------|---------------------|--------|
| `architect` | yes | yes — full brief | Long-form blueprint posted as a GitHub issue comment |
| `explorer` | no | no — only architect's targeted question | Research note (facts, paths, line numbers) |
| `designer`  | no | no — only architect's targeted question | Recommendation note (UX / naming / contract / PII trade-off + rationale) |

### Architect-as-lead

In a discovery crew the architect IS the team-lead. The architect:

1. Reads the mission brief (the batch of issues to be planned).
2. For each issue, identifies the open questions that block a confident blueprint.
3. `SendMessage`s the explorer or designer with the **scoped question only** — not the mission brief.
4. Synthesizes the replies into a blueprint comment posted to the GitHub issue.
5. Repeats per issue until the batch is done.
6. `SendMessage`s the orchestrator with the comment URLs once every issue in the batch has its blueprint.

The architect's regular blueprint quality bar (scope, file plan, sequence, interface contracts, edge cases, verify steps — see `agents/architect.md`) still applies. Discovery just changes where the blueprint lands (issue comment vs. handed to a builder).

### Explorer scope

Read-only code investigation. The explorer answers questions like:

- "Where is `<feature>` currently handled? Cite files and line ranges."
- "What pattern does the codebase use for `<concern>` today?"
- "Is `<library>` already a dependency? Which version, and which call sites?"

The explorer returns **facts**, not opinions: file paths, line numbers, current patterns, citations. If the architect wants a recommendation, that's a designer question, not an explorer question.

The explorer's existing read-only discipline (`agents/explorer.md`) and "cite, don't infer" rule apply unchanged.

### Designer scope

UX, naming, contract, and PII decisions. The designer answers questions like:

- "Should this field be exposed in the public API or kept internal? Why?"
- "What should we name the new `<thing>`? Constraints: `<list>`."
- "This data includes `<PII candidate>` — does it need redaction at the boundary?"
- "User flow needs `<X>`. Recommend the entry point and exit condition."

The designer returns **crisp recommendations + rationale**. Not "here are three options" — pick one, explain why, note the alternative if it's close.

The designer's existing UX-brief discipline (`agents/designer.md`) applies, but discovery responses are typically shorter than a full UX brief — one decision, one rationale, sometimes a flow sketch.

### Mission-agnostic spawn for support roles

The explorer and designer are spawned for the **batch**, not per-issue, but they should NOT see the full mission brief. They react to architect's targeted questions one at a time.

Why: keeping the support roles mission-agnostic prevents them from anticipating questions or volunteering context the architect didn't ask for. The architect owns the synthesis. If the explorer/designer second-guess the framing, the blueprint drifts and the architect loses the ability to keep the batch consistent.

In practice: spawn explorer and designer with a one-line mission ("you are the discovery-batch explorer; the architect will route scoped questions to you"). Do not include the issue list, the high-level goal, or the architect's working theory.

## Deliverable shape

The discovery crew produces **long-form GitHub issue comments**. Not PRs. Not files in the repo. Not draft documents in someone's scratchpad.

Each blueprint comment lives on the issue it plans. The architect posts it via `gh issue comment <issue> --body-file <path>`. The body follows the architect's standard blueprint sections:

1. **Scope** — what's in/out, the invariant being protected.
2. **File plan** — files to create/modify/delete, one-line per file.
3. **Sequence** — ordered implementation steps with verify gates.
4. **Interface contracts** — signatures + behaviour summaries for new public surfaces.
5. **Edge cases** — empty/zero, concurrent, errors, backwards compat.
6. **Verify steps** — exact commands the builder runs end-to-end.

Plus a discovery-only header noting the support sources:

```markdown
> Blueprint produced by discovery crew `<team-name>`.
> Explorer note: <one-line summary>
> Designer note: <one-line summary>
```

The header is short on purpose — it's a provenance line, not a recap. The full blueprint sections carry the substance.

## Stop condition

The discovery crew is done when **every issue in the batch has its blueprint comment**. The architect tracks this via the team task list (one task per issue, marked completed when the comment is posted) and confirms the count against the mission brief.

When done, the architect `SendMessage`s the orchestrator with:

- The team name.
- The list of `(issue number, comment URL)` pairs, one per planned issue.
- A one-line note on any issue that was punted (e.g. "issue #1234 needs upstream API doc — punted, see comment").

The orchestrator is responsible for shutting the crew down per the standard cooperative-shutdown protocol.

## Worked example

Mission: blueprint a batch of three issues about adding pagination to a list endpoint.

### 1. Architect → explorer dispatch

The architect identifies that the blueprint needs to know how the existing list endpoint is structured.

```
SendMessage({
  to: "explorer",
  message: "For issue #821: where is the GET /api/items endpoint defined? I need the handler file, the query builder it uses, and any existing limit/offset handling. Cite file paths and line ranges."
})
```

### 2. Explorer reply

```
SendMessage({
  to: "architect",
  message: "Handler: src/api/items.ts:42-78 (function `listItems`). Query builder: src/db/queries/items.ts:15-34 — uses Drizzle's `select().from(items)` with no limit/offset today. No existing pagination middleware in the request pipeline (verified by grep across src/api/middleware/). Confidence: high."
})
```

_Routing note: the explorer's role contract (`agents/explorer.md`) specifies replies addressed to `"team-lead"`. In a `kind: discovery` crew the architect IS the team-lead, so `to: "architect"` and `to: "team-lead"` route to the same inbox. Either form is valid; this example uses `"architect"` for clarity about which role receives the research note._

### 3. Architect → designer dispatch

The architect now needs the contract decision: cursor-based or offset-based pagination, and what the response envelope looks like.

```
SendMessage({
  to: "designer",
  message: "For issue #821: pagination contract for GET /api/items. Constraints — list is ordered by `created_at desc`, expected page size 20-100, clients are mostly first-party web. Recommend cursor vs offset and the response envelope shape. One pick + rationale."
})
```

### 4. Designer reply

```
SendMessage({
  to: "architect",
  message: "Recommend cursor-based pagination keyed on `(created_at, id)`. Rationale: the list is append-mostly so offset would drift as new items land between page fetches, producing duplicate/missed rows for first-party clients that paginate while the user scrolls. Envelope: `{ items: T[], next_cursor: string | null }`. Cursor is an opaque base64 of `${created_at}:${id}`. Alternative considered: offset — rejected for the drift reason."
})
```

### 5. Architect synthesis

The architect drafts the blueprint and posts it.

```markdown
> Blueprint produced by discovery crew `repo-alpha`.
> Explorer note: handler at src/api/items.ts:42-78, query builder at src/db/queries/items.ts:15-34, no existing pagination middleware.
> Designer note: cursor-based pagination on `(created_at, id)`, envelope `{ items, next_cursor }`, opaque base64 cursor.

## Scope
Add cursor-based pagination to GET /api/items. Protects the invariant that a client paging through the list never sees duplicates or skips items, even when new items are inserted mid-scroll.

## File plan
- `src/api/items.ts` — extend `listItems` to accept `?cursor=<opaque>&limit=<n>`, return `{ items, next_cursor }`.
- `src/db/queries/items.ts` — extend the query builder to accept a `(created_at, id)` cursor predicate.
- `src/api/cursor.ts` — new: encode/decode the opaque cursor (base64 of `${created_at}:${id}`).
- `tests/api/items.pagination.test.ts` — new: covers first page, mid-scroll insert, last page (`next_cursor: null`), invalid cursor.

## Sequence
1. Add cursor encode/decode helpers in `src/api/cursor.ts`. Verify: `npx tsc --noEmit`, `npm test`.
2. Extend the query builder to accept the cursor predicate. Verify: `npm test`.
3. Wire pagination into the handler, default `limit=20`, cap `limit<=100`. Verify: `npm test`.
4. End-to-end: run the new pagination test and the full `npm test` suite.

## Interface contracts
- `encodeCursor(row: { created_at: Date, id: string }): string` — returns opaque base64.
- `decodeCursor(s: string): { created_at: Date, id: string }` — throws `InvalidCursorError` on malformed input.
- Endpoint response: `{ items: Item[], next_cursor: string | null }`.

## Edge cases
- Empty result set: `{ items: [], next_cursor: null }`.
- Single page (rows < limit): `next_cursor: null`.
- Invalid cursor: 400 with `{ error: "invalid_cursor" }`.
- Concurrent inserts mid-scroll: cursor predicate is `(created_at, id) < cursor`, so newer rows never appear in subsequent pages.
- Backwards compat: requests without `?cursor` default to first page; existing first-party clients keep working.

## Verify steps
1. `npx tsc --noEmit`
2. `npm test` — full suite, including `tests/api/items.pagination.test.ts`.

_Substitute the concrete commands from your team's `squadkit.json` (or equivalent verify config) before posting; the architect resolves these at synthesis time, not at template-render time._
```

The architect posts this with `gh issue comment 821 --body-file <path>`, marks the task complete, and moves on to the next issue in the batch. Once issues #821, #822, #823 all have their blueprint comments, the architect notifies the orchestrator with the URLs and the crew shuts down.

## See also

- `agents/architect.md` — base architect role contract (execution crew default).
- `agents/explorer.md` — explorer role contract (read-only investigation).
- `agents/designer.md` — designer role contract (UX briefs, accessibility).
- `skills/spawn-team/SKILL.md` — how crews are materialized.
