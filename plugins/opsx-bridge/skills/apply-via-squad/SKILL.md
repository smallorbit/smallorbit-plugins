---
name: apply-via-squad
description: Dispatch an OpenSpec change to a squadkit crew. Reads openspec/changes/<name>/, derives a squad profile from the proposal's ## Capabilities (one builder per unique capability, capped at 4, default 1 when none), and invokes /squadkit:spawn-team with the proposal + design as briefs on an epic branch. Reconciles tasks.md after the crew's PRs land.
triggers:
  - "/opsx-bridge:apply-via-squad"
  - "apply via squad"
  - "apply change via squad"
  - "dispatch change to squad"
  - "spawn a squad for change"
allowed-tools: Bash, Read, Edit, Skill
---

# Apply via Squad

Bridge a single OpenSpec change to a coordinated squadkit crew. The skill reads `openspec/changes/<name>/`, derives a crew profile from the proposal's `## Capabilities` (the universal unit of work — see D3), and hands the proposal + design off to `/squadkit:spawn-team` as the architect's mission brief. After the crew's PRs land, it reconciles completed sections back into `tasks.md` so `/opsx:archive` works.

The bridge is **additive** — it calls `spawn-team` as a black box through its public flag surface and never modifies squadkit, opsx, or the change proposal.

## Input

`$ARGUMENTS` — the change name (positional) plus optional flags.

| Argument | Default | Effect |
|----------|---------|--------|
| `<change-name>` | required | Directory under `openspec/changes/`. Resolved by `read-change`. |
| `--profile <name>` | derived | Named crew profile to pass through to spawn-team. When present, **skips** capability-based builder derivation (D3). |
| `--base <branch>` | resolved | Override the base branch the epic is cut from. See base resolution below. |
| `--no-epic` | epic on | Suppress the `--epic` flag; the crew commits directly against the resolved base branch instead of a feature epic branch (D5). |

`--profile` and the derived builder count are mutually exclusive — when `--profile` is given the bridge does not compute `--builders`.

## Process

### 1. Preflight — read and validate the change

Invoke the internal `read-change` sub-skill for the named change. Consume its documented JSON output contract (`capabilities`, `applyReady`, `applyRequires`); do not re-parse the change directory here.

```
Skill({skill: "opsx-bridge:read-change", args: "<change-name>"})
```

**Change not found.** `read-change` exits non-zero with a stderr message when `openspec/changes/<name>/` does not exist. On that failure, refuse to dispatch and list available changes so the operator can correct the name:

```bash
openspec list --json | jq -r '.[].name'
```

Report: `apply-via-squad: no change "<name>". Available: <list>.`

**Apply-readiness.** The readiness GATE consumes `read-change`'s `applyReady` boolean (= `openspec status`'s `.isComplete`). Dispatch only when `applyReady` is `true`.

`read-change` flattens `applyRequires` to a `string[]` of artifact names — it carries no per-artifact status. So when the gate is closed and the bridge needs to report *which* required artifacts are still incomplete, it sources that status detail by re-querying the CLI directly (the source of truth):

```bash
STATUS=$(openspec status --change "<name>" --json)
```

If `applyReady` is `false`:

- Refuse to dispatch.
- Re-query `openspec status` to report which `applyRequires` artifacts are incomplete (name + current status from the CLI, not from `read-change`).
- Suggest completing them: `Run /opsx:propose <name> to finish the outstanding artifacts, then re-run apply-via-squad.`

This mirrors the spec's "Apply-readiness unsatisfied" scenario — the bridge proceeds only when readiness is satisfied.

### 2. Resolve the base branch

Never hardcode `develop` or `main`. Resolve `$BASE` in order, stopping at the first non-empty result (D5):

1. `--base <branch>` flag (per-invocation override).
2. `git config claude.flowkit.prBase` (operator session pin).
3. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub default).

```bash
BASE="${BASE_FLAG:-$(git config claude.flowkit.prBase 2>/dev/null)}"
[ -n "$BASE" ] || BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
```

`spawn-team` cuts the epic branch from its own configured base; the bridge surfaces `$BASE` to the operator so the resolved target is explicit, and passes `--base` through when overriding.

### 3. Derive the crew profile from capabilities

Skip this step when `--profile <name>` was passed — pass that profile through to spawn-team verbatim and let it size the crew (D3, "Explicit profile override").

Otherwise derive the builder count from `read-change`'s `capabilities` array:

- `N = number of unique capabilities` (New + Modified, already de-duplicated by read-change).
- Builder count = `min(N, 4)` — one builder per capability, capped at 4.
- When `N == 0` (no-specs change — proposal.md + tasks.md only, per D8), default to **1** builder. The bridge does **not** refuse; OpenSpec only requires `tasks` for apply-readiness and the bridge respects that contract.

```bash
N=$(jq 'length' <<<"$CAPABILITIES")
if [ "$N" -eq 0 ]; then BUILDERS=1; elif [ "$N" -gt 4 ]; then BUILDERS=4; else BUILDERS="$N"; fi
```

The default crew shape is `1 architect + N builders + 1 reviewer + 1 tester`, expressed by passing `--builders <BUILDERS>` against spawn-team's default profile. The architect coordinates; the bridge does not invent a new profile format.

### 4. Compose the briefs

Pass the proposal as a brief always; add the design brief only when `design.md` exists and is non-empty (spec scenarios "Proposal and design both present" / "Proposal only"):

```bash
BRIEFS=(--brief "@openspec/changes/<name>/proposal.md")
DESIGN="openspec/changes/<name>/design.md"
[ -s "$DESIGN" ] && BRIEFS+=(--brief "@$DESIGN")
```

`spawn-team` reads each `@path` and embeds the concatenated content into the architect's spawn prompt under `## Mission brief`. Only the architect receives the brief; other roles get scoped tasks from the lead.

### 5. Compose the epic flag

Include `--epic <change-name>` by default so the crew works on `feature/<change-name>-<parent-issue>` cut from the resolved base (D5, "Default epic mode"). Suppress it when the operator passed `--no-epic` — the squad then commits directly against the resolved base (spec scenario "Operator disables epic"):

```bash
EPIC=(--epic "<change-name>")
[ -n "$NO_EPIC" ] && EPIC=()
```

**Known limitation — `--no-epic` cannot fully suppress spawn-team's epic prompt.** squadkit exposes no `--no-epic` flag. When `--epic` is omitted, spawn-team's documented behavior is to *prompt* for epic confirmation (an `AskUserQuestion`) rather than silently skip the epic. `--mode none` sets the member permission mode only — it does NOT suppress that confirmation prompt. So under `--no-epic` the operator will still see spawn-team's epic-confirmation prompt; the intended contract is that they answer it "use base branch" to keep the crew on the resolved base. A future squadkit `--no-epic` flag would let the bridge pass through and close this loop; until then this is a known, documented interaction the bridge cannot eliminate from its side.

### 6. Dispatch to spawn-team

Compose the full invocation from the pieces above and dispatch via the Skill tool. The bridge is a non-interactive caller, so it MUST pass an explicit `--mode` (spawn-team prompts only for `--mode inherit`); default to `--mode none` so the operator's harness defaults apply unless they say otherwise.

With derived builders (no `--profile`):

```
Skill({skill: "squadkit:spawn-team",
       args: "--builders <BUILDERS> <EPIC> <BRIEFS> --mode none"})
```

With an explicit profile override:

```
Skill({skill: "squadkit:spawn-team",
       args: "--profile <name> <EPIC> <BRIEFS> --mode none"})
```

Show the operator the constructed argument string before dispatching. Example (this very change — one capability `opsx-bridge`, proposal + design both present):

```
/squadkit:spawn-team --builders 1 --epic opsx-bridge \
  --brief @openspec/changes/opsx-bridge/proposal.md \
  --brief @openspec/changes/opsx-bridge/design.md \
  --mode none
```

spawn-team owns the rest: epic-branch cut (inline `git`/`gh` block since flowkit v4 removed `cut-epic`), worktree provisioning, member spawn, and the dispatch loop. The bridge does not micromanage the crew.

### 7. Post-completion reconciliation

After the crew's PRs land, reconcile `tasks.md`. Detect completion by matching merged PRs for issues labeled `opsx-change:<name>`:

```bash
gh pr list --search "label:opsx-change:<name> is:merged" --state merged --limit 200 \
  --json number,title,body
```

For each `tasks.md` section whose corresponding work has landed (a matching merged PR), mark every `- [ ]` item in that section `- [x]` via `Edit`. Then:

- **All sections complete** — every section has a matching merged PR: mark all tasks `[x]` and suggest `/opsx:archive <name>`. Confirm via `openspec status --change <name> --json` (`isComplete: true`).
- **Partial completion** — only some sections have merged PRs: mark **only** the completed sections' tasks `[x]`, leave incomplete sections untouched, and report which sections remain.

**Never mutate `tasks.md` for failed or incomplete sections** (D7). The operator decides whether to re-run for the unfinished work.

### 8. Failure surfacing — no retry

If a squad member fails its verify gate or stops responding, surface the member name and its current task, and **do not** mutate `tasks.md` for that section (D7). The bridge **never auto-retries** — a failure is a signal for human attention. The operator inspects the crew, fixes the blocker, and re-invokes if they choose.

## Notes

- **Stack-agnostic.** The bridge sizes the crew from OpenSpec capabilities, never from `plugin.json`, directory structure, or any release unit. A capability may map to a plugin, a package, a service, or a logical grouping the spec author chose.
- **read-change is the parser.** This skill consumes read-change's payload; it does not re-implement capability parsing or apply-readiness derivation. Apply-readiness is *reported* by read-change and *enforced* here.
- **spawn-team is a black box.** apply-via-squad composes valid spawn-team flags (`--profile`, `--builders`, `--epic`, `--brief @path`, `--mode`) and dispatches. It never inspects or modifies squadkit internals.

## Composition

| Calls | Why |
|-------|-----|
| `opsx-bridge:read-change` | Parse the change into capabilities + apply-readiness (preflight). |
| `squadkit:spawn-team` | Materialize the crew with the derived/overridden profile, briefs, and epic. |
