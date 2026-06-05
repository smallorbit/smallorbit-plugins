## Context

This repo recently adopted OpenSpec (`@fission-ai/openspec` CLI v1.3.1) and committed the `/opsx:propose`, `/opsx:apply`, `/opsx:explore`, `/opsx:archive` slash commands under `.claude/commands/opsx/`. OpenSpec's stock `/opsx:apply` is a **single-agent task-loop runner** — it reads `openspec/changes/<name>/tasks.md` and walks each `- [ ]` linearly in one Claude conversation, ticking items off as it goes.

This monorepo already ships two dispatchers tailored to multi-plugin / multi-issue work:

- **`/squadkit:spawn-team`** — coordinated crew (architect + N builders + reviewer + tester), each in its own worktree, with cross-role communication via SendMessage. Best for cross-plugin design work.
- **`/swarmkit:swarm`** — parallel isolated-worktree agents, one per GitHub issue, with topological dispatch respecting blocked-by edges and an automatic review/fix pass per PR. Best for paralle issue execution.

Neither dispatcher knows about OpenSpec. opsx does not know about either dispatcher. They are three independent systems that today require a human to mentally translate between.

The flowkit v4 epic (proposal at `openspec/changes/flowkit-v4-github-flow/`, GH parent #987, sub-issues #982–#986) is the immediate forcing function — it spans 3 plugins, has 32 tasks across 5 issues, and is the wrong shape for `/opsx:apply` to run linearly.

## Goals / Non-Goals

**Goals:**

- Bridge a single OpenSpec change proposal to either dispatcher with one slash command.
- **Additive only** — zero modifications to opsx command files, zero modifications to squadkit or swarmkit skills/specs.
- Operator picks the dispatcher explicitly (`apply-via-squad` vs `apply-via-swarm`), the bridge does not auto-route.
- Reconcile dispatcher completion back into `tasks.md` so `/opsx:archive` works afterward.
- Surface failure modes (worker died, verify failed) without corrupting `tasks.md`.

**Non-Goals:**

- Replacing `/opsx:apply` for single-agent linear changes (still the right tool there).
- Making squadkit or swarmkit "opsx-aware" — coupling either to OpenSpec is rejected.
- Auto-deciding squad vs swarm based on change shape — the operator knows the answer.
- Building a third dispatcher.
- Mixed-mode (some tasks via squad, some via swarm in one change) — punted to v2 if ever needed.

## Decisions

### D1: Plugin layout

```
plugins/opsx-bridge/
  plugin.json
  skills/
    apply-via-squad/
      SKILL.md
    apply-via-swarm/
      SKILL.md
    read-change/             # internal sub-skill
      SKILL.md
  openspec/
    specs/opsx-bridge/
      spec.md
```

**Why two top-level skills, not one with a flag**: keeps the slash-command surface explicit (operator types `/opsx-bridge:apply-via-swarm`, no `--mode swarm` flag to forget). Matches how `/swarmkit:swarm` and `/swarmkit:swarm` cohabit. Sub-skill `read-change` is internal and not user-facing — it parses the change directory and returns structured data.

**Alternative rejected**: single skill `/opsx-bridge:apply <change> --via squad|swarm`. Saves one file but obscures the two distinct workflows.

### D2: Task-to-issue mapping for the swarm path

**Decision: section-grouped, GH-issue-backed, with dual dependency-wiring sources.**

`tasks.md` items are grouped by their parent `##` heading (section). Each section maps to **one GitHub issue**. The bridge:

1. Reads `tasks.md`, parses sections, computes a stable section ID (e.g. `slug(heading)`).
2. Looks up existing issues with label `opsx-change:<change-name>` and an issue-body marker `<!-- opsx-section: <section-id> -->`.
3. If found → uses the issue. If not → files a new issue with the section's tasks inlined as a checklist.
4. Computes blocked-by edges from **two sources, merged**:
   - **Inline markers** in section headers: `## Section B <!-- depends: section-a -->` (co-located, easiest to keep in sync with the section itself).
   - **Explicit `## Dependencies` block** at end of tasks.md: `Section B blocked by Section A` (useful for cross-cutting deps or when retro-wiring an existing tasks.md).
   - Conflict resolution: union of both sets. Duplicate edges deduped.
5. Passes the issue list (in topological order) to `/swarmkit:swarm`.

**Why sections, not per-task**: tasks.md often has 30+ tasks; one issue per task drowns the GH project. Sections (typically 4–8 per change) match swarm's natural granularity of "one PR per issue."

**Why GH issues, not bypass**: `/swarmkit:swarm` is built on per-issue dispatch and per-PR review. Bypassing GH would lose the review pass — the main reason to pick swarm over plain swarm.

**Alternatives rejected**:
- 1:1 task↔issue: too many issues, drowns the board.
- Skip GH entirely, feed sections as worker briefs: loses swarm's PR review.
- Per-spec-file grouping: works for v4 but not for changes that don't modify specs proportionally.

### D3: Squad-path profile derivation

For `apply-via-squad`, the bridge derives a squad profile from the change artifacts using **OpenSpec capabilities** as the universal unit of work — not plugins, packages, services, or modules. OpenSpec's `## Capabilities` section in proposal.md is already the canonical "what's being touched" abstraction:

| Artifact read | Used to determine |
|---|---|
| `proposal.md` → `## Capabilities` (New + Modified, unique) | Builder count: one per unique capability |
| `tasks.md` section count | Optional sanity check on builder count |
| `specs/<cap>/spec.md` delta types | If only `## ADDED Requirements` → lighter review; if `## MODIFIED/REMOVED` → mandatory reviewer + tester |
| Crew shape (`kind:`) | Default `execution`; user can override `--kind discovery` |

**Default profile**: 1 architect + N builders (one per unique capability, capped at 4) + 1 reviewer + 1 tester.

**No-capabilities fallback** (e.g. a change with only proposal.md + tasks.md, no specs/): default to 1 builder. Bridge proceeds gracefully — see D8.

**Why capabilities are the right unit**: in a plugin monorepo, capabilities typically map 1:1 to plugins (each plugin owns its spec namespace). In a non-monorepo (single-package, multi-service, multi-package workspace), capabilities are whatever the spec author named — could be `user-auth`, `checkout`, `notifications`. The bridge is stack-agnostic: it never reads `plugin.json`, never inspects directory structure, never assumes a release unit. It only consumes OpenSpec's own abstractions.

**Override**: `--profile <name>` to use a named profile from `~/.claude/profiles/`, identical to how `spawn-team` accepts profiles today. Bridge does not invent new profile format.

### D4: Brief passing

Both paths pass the proposal + design as the briefing context:

- **Squad path**: invokes `spawn-team` with `--brief @openspec/changes/<name>/proposal.md @openspec/changes/<name>/design.md` (multiple `--brief` arguments concatenated). The architect crew member receives both.
- **Swarm path**: each filed GH issue body includes a footer pointing at the change directory, so the per-issue agent reads `openspec/changes/<name>/proposal.md` and `design.md` as part of its initial orientation.

### D5: Base branch resolution (no hardcoding)

The bridge **never hardcodes** `develop`, `main`, or any specific base branch. Resolution order on every invocation:

1. `--base <branch>` flag (operator override per invocation)
2. `claude.flowkit.prBase` git config (operator-pinned for the session)
3. flowkit's resolved base for the repo (read via flowkit primitives if installed)
4. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub default)

This works whether the repo is on **v3 flow** (target = develop), **v4 flow** (target = main), or neither (just whatever GitHub thinks the default is). flowkit's own migration from develop→main lands without requiring any bridge changes — the bridge already asks flowkit for the answer.

- **Squad path**: passes `--epic <change-name>` to `spawn-team`, which cuts `feature/<change-name>-<parent-issue>` off the resolved base branch (using `flowkit:cut-epic` under the hood). All builder PRs target the epic branch.
- **Swarm path**: no epic by default — each issue → own PR → target = resolved base. Operator can pass `--base <branch>` to scope to a feature branch if they're staging a coordinated landing.

### D6: Post-completion reconciliation

After the dispatched workers/squad complete (detected by `gh pr list --search "label:opsx-change:<name> is:merged"` matching all issues):

1. Bridge re-reads `tasks.md` and marks all tasks in completed sections as `[x]`.
2. Runs `openspec status --change <name>` and reports remaining incomplete artifacts.
3. Suggests `/opsx:archive <name>` if `isComplete: true`.

If only some sections complete (partial), bridge marks only those sections' tasks complete and reports remaining work. The operator decides whether to re-run for the unfinished sections.

### D7: Failure handling

- **Squad path**: if a builder fails verify gate or doesn't respond, bridge reports the member name and current task. `tasks.md` is **not** mutated for incomplete sections.
- **Swarm path**: if a per-issue worker fails (PR closed without merge, or stuck), bridge reports the issue number. Operator can re-invoke `apply-via-swarm` and the bridge will only dispatch agents for issues without a matching merged PR.

Bridge never auto-retries — failure is a signal for human attention.

## Risks / Trade-offs

- **[Risk]** Section parsing of `tasks.md` is convention-dependent. If an opsx change doesn't use `##` headings, sections collapse to one issue per change. → **Mitigation**: document the convention in `opsx-bridge`'s SKILL.md; opsx's own `/opsx:propose` already generates sectioned tasks.md.

- **[Risk]** GH issue / tasks.md drift — issues edited on GH not reflected in tasks.md. → **Mitigation**: tasks.md is authoritative for *which tasks exist*; issue body is regenerated from tasks.md on each `apply-via-swarm` invocation (preserving user comments via append-only).

- **[Risk]** Architect in squad path doesn't know about opsx's archive flow. → **Mitigation**: bridge handles archive reconciliation itself in D6; architect just produces working code.

- **[Trade-off]** Two dispatch paths mean two SKILL.md files with overlapping "read change directory" logic. → **Mitigation**: shared `read-change` sub-skill returns a parsed JSON struct (proposal capabilities, tasks-by-section, applyRequires status).

- **[Trade-off]** Bridge adds latency — one extra layer between operator intent and worker dispatch. → **Mitigation**: bridge logic is read-only parse + delegate; the actual work happens in spawn-team / swarm. Bridge overhead is single-digit seconds.

- **[Trade-off]** Operator must know which dispatcher to pick. → **Mitigation**: bridge SKILL.md includes a "which to pick" decision table at the top; mirrors how operators already pick squad vs swarm today.

### D9: Swarm single-parent linearization

swarm's stacked-PR model is **single-parent**: each dependent agent branches from exactly one parent's branch tip (`git checkout -b worktree-agent-<this> origin/worktree-agent-<dependency>`) and its PR targets that one parent. swarm builds the stack from the native `blockedBy` edges it reads off the issues — not from the order issue numbers arrive in — and has no multi-parent/diamond handling.

An OpenSpec change's true dependency graph can be a **diamond** (a section depending on two others — a fan-in), which cannot be wired natively as-is: swarm would read two `blockedBy` edges on the fan-in node and hit the undocumented diamond case.

**Decision: linearize the edges that get wired, not just the dispatch order.** Take the union edge set, topologically sort the section-issues, and derive a **linear chain** where each issue is blocked_by *only its immediate predecessor* in that order. Wire those chain edges as the native `blockedBy` connection. swarm then reads exactly one parent per node and produces a clean single-parent stack.

This is correctness-preserving when sections touch disjoint files (the common case — sections map to distinct capabilities/areas): in a linear stack each branch transitively contains all its true ancestors' work, so every original dependency is satisfied through the chain. It only ever over-constrains ordering, never under-constrains it.

Discovered dogfooding this plugin: the opsx-bridge change graph had #993 (section 5, capability files) depending on **both** #991 (apply-via-squad) and #992 (apply-via-swarm) — a diamond fan-in. Linearizing to `#990 → #991 → #992 → #993 → #994 → #995` and wiring each node blocked_by only its predecessor lets swarm chain each as a single-parent stack while still respecting every original blocked-by edge transitively.

### D8: No-specs fallback

If a change has only `proposal.md` + `tasks.md` and no `specs/` deltas (legitimate for changes that don't modify behavior contracts — e.g. refactors, docs, infra):

- **Squad path**: builder count defaults to 1. Profile: 1 architect + 1 builder + 1 reviewer + 1 tester. Operator can still override via `--profile`.
- **Swarm path**: unaffected — section count drives issue count regardless of specs/.

The bridge **does not refuse** to run on no-specs changes. OpenSpec itself only requires `tasks` for apply-readiness (`applyRequires: ["tasks"]`), and the bridge respects that contract.

## Migration Plan

No migration — this is purely additive. Existing `/opsx:apply` continues to work. Existing `/squadkit:spawn-team` and `/swarmkit:swarm` continue to work. Bridge adds two new entry points.

Rollback: revert the plugin's directory; nothing else needs touching.

## Resolved Decisions

The following sub-decisions are locked in (previously listed as open questions):

| ID | Question | Resolution |
|---|---|---|
| Q1 | Skill naming | `apply-via-squad` / `apply-via-swarm` — parallels `/opsx:apply` and reads cleanly. |
| Q2 | Section dependency wiring | Both `<!-- depends: section-id -->` inline markers AND `## Dependencies` block; union both sets. |
| Q3 | Add `apply-via-opsx`? | No. Operators invoke `/opsx:apply` directly for single-agent mode. |
| Q4 | `read-change` visibility | Internal sub-skill only; not advertised to operators. Promote if a second consumer emerges. |
| Q5 | No-specs changes | Handle gracefully — see D8. |
