# opsx-bridge — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `<repo-root>/`.

> **Citation-stability note.** This REFERENCES.md was authored from a swarm worker
> branch cut before the apply-via-squad (#997) and apply-via-swarm (#998) fix-rounds
> landed on their parent branches, so the cited line numbers in those two files are
> **pre-fix** and have drifted in the integrated tree. Citations remain useful because
> each is also anchored to a process-step heading and a short quoted snippet — find the
> snippet, and the surrounding lines are the right region. A `/spec-baseline` audit
> pass against the integrated tree will reconcile the exact line numbers; until then,
> trust the headings and snippets over the line numbers for `apply-via-squad` and
> `apply-via-swarm`. `read-change/SKILL.md` citations were authored against the same
> file state that landed, so its line numbers are accurate.

Both bridge skills (`apply-via-squad` and `apply-via-swarm`) implement the cross-cutting
requirements — change discovery, apply-readiness, base resolution, reconciliation, and
failure surfacing — verbatim so they stay consistent; those requirements cite both files.

---

## Requirement: Change discovery by name

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:42-48` — step 1 "Change not found." block: `read-change` exits non-zero when `openspec/changes/<name>/` does not exist; the bridge lists `openspec list --json | jq -r '.[].name'` and reports `apply-via-squad: no change "<name>". Available: <list>.`
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:44-50` — step 1 "Change not found." block: same contract for the swarm path.
- `plugins/opsx-bridge/skills/read-change/SKILL.md:39-43` — `CHANGE_DIR="openspec/changes/$NAME"; [ -d "$CHANGE_DIR" ] || { ... exit 1; }` — the directory-existence resolution itself.

### Scenario: Change name matches existing directory
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:40-42` — `CHANGE_DIR` resolved from the name; existing directory passes the `[ -d ... ]` guard and the skill proceeds (consumed as preflight by both dispatch skills, e.g. `apply-via-squad/SKILL.md:34-39` step 1 "Preflight — read and validate the change").
**Interpolated; no direct test.**

### Scenario: Change name does not match
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:42-48` — "Change not found." block lists available changes via `openspec list --json`. Mirror in `apply-via-swarm/SKILL.md:44-50`.
**Interpolated; no direct test.**

---

## Requirement: Apply-readiness validation

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:50-62` — step 1 "Apply-readiness." block: `STATUS=$(openspec status --change "<name>" --json)`, "Every artifact named in `applyRequires` must have `status: "done"`", refuse + suggest `/opsx:propose <name>` otherwise.
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:54-66` — step 1 "Apply-readiness." block: identical contract for the swarm path.
- `plugins/opsx-bridge/skills/read-change/SKILL.md:50-53` — `STATUS=$(openspec status --change "$NAME" --json)`, `APPLY_READY=$(jq -r '.isComplete' ...)`, `APPLY_REQUIRES=$(jq -c '.applyRequires' ...)` — the readiness fields the bridge enforces.

### Scenario: Apply-readiness satisfied
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:62` — "the bridge proceeds only when readiness is satisfied." Mirror in `apply-via-swarm/SKILL.md:66`.
**Interpolated; no direct test.**

### Scenario: Apply-readiness unsatisfied
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:56-60` — "If any required artifact is not `done`: Refuse to dispatch. Report which `applyRequires` artifacts are incomplete ... Suggest ... `/opsx:propose <name>`". Mirror in `apply-via-swarm/SKILL.md:60-64`.
**Interpolated; no direct test.**

---

## Requirement: Base branch resolution

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:64-75` — step 2 "Resolve the base branch": "Never hardcode `develop` or `main`", precedence `--base` → `git config claude.flowkit.prBase` → `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, with the `BASE="${BASE_FLAG:-$(git config claude.flowkit.prBase ...)}"` snippet.
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:68-79` — step 2 "Resolve the base branch": "Identical to `apply-via-squad` step 2 — shared logic", same precedence + snippet.

### Scenario: Explicit --base flag
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:68` — precedence item 1 "`--base <branch>` flag (per-invocation override)." Mirror in `apply-via-swarm/SKILL.md:72`.
**Interpolated; no direct test.**

### Scenario: Session-pinned base
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:69` — precedence item 2 "`git config claude.flowkit.prBase` (operator session pin)." Mirror in `apply-via-swarm/SKILL.md:73`.
**Interpolated; no direct test.**

### Scenario: GitHub default fallback
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:70` — precedence item 3 "`gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub default)." Mirror in `apply-via-swarm/SKILL.md:74`.
**Interpolated; no direct test.**

---

## Requirement: Squad path builder derivation from capabilities

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:79-94` — step 3 "Derive the crew profile from capabilities": `N = number of unique capabilities`, `Builder count = min(N, 4)`, `N == 0 → 1 builder`, skip when `--profile` given. Snippet at `:90-92` (`if [ "$N" -eq 0 ]; then BUILDERS=1; elif [ "$N" -gt 4 ]; then BUILDERS=4; else BUILDERS="$N"; fi`).

### Scenario: Multiple capabilities
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:86` — "Builder count = `min(N, 4)` — one builder per capability, capped at 4." (`N <= 4` branch yields `BUILDERS="$N"` at `:91`).
**Interpolated; no direct test.**

### Scenario: Capability count exceeds cap
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:91` — `elif [ "$N" -gt 4 ]; then BUILDERS=4` caps the count at 4.
**Interpolated; no direct test.**

### Scenario: No capabilities (no-specs change)
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:87` — "When `N == 0` ... default to **1** builder. The bridge does **not** refuse". Snippet `if [ "$N" -eq 0 ]; then BUILDERS=1` at `:91`.
**Interpolated; no direct test.**

### Scenario: Explicit profile override
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:81` — "Skip this step when `--profile <name>` was passed — pass that profile through to spawn-team verbatim". Also the `--profile` input row at `:26`.
**Interpolated; no direct test.**

---

## Requirement: Squad path brief passing

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:96-106` — step 4 "Compose the briefs": `BRIEFS=(--brief "@openspec/changes/<name>/proposal.md")`, `[ -s "$DESIGN" ] && BRIEFS+=(--brief "@$DESIGN")`.

### Scenario: Proposal and design both present
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:100-103` — both briefs appended when `design.md` exists and is non-empty (`[ -s "$DESIGN" ]`).
**Interpolated; no direct test.**

### Scenario: Proposal only
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:98` — "add the design brief only when `design.md` exists and is non-empty" (the `-s` guard at `:103` is false → proposal-only).
**Interpolated; no direct test.**

---

## Requirement: Squad path epic branch handling

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:108-115` — step 5 "Compose the epic flag": `EPIC=(--epic "<change-name>")` by default, `[ -n "$NO_EPIC" ] && EPIC=()`.

### Scenario: Default epic mode
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:110` — "Include `--epic <change-name>` by default so the crew works on `feature/<change-name>-<parent-issue>` cut from the resolved base". Snippet `EPIC=(--epic "<change-name>")` at `:113`.
**Interpolated; no direct test.**

### Scenario: Operator disables epic
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:114` — `[ -n "$NO_EPIC" ] && EPIC=()` suppresses the flag; "the squad then commits directly against the resolved base" at `:110`. Input row `--no-epic` at `:28`.
**Interpolated; no direct test.**

---

## Requirement: Swarm path section grouping

**Sources**
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:91-98` — step 4 "Group tasks into section-issues": one section maps to one GitHub issue; N sections → N issue groupings; no `##` headings → single grouping keyed on the change-name slug.
- `plugins/opsx-bridge/skills/read-change/SKILL.md:80-96` — step 4 "Parse tasks grouped by section": group every `- [ ]`/`- [x]` under nearest `##`, exclude `## Dependencies`, single implicit section when no headings exist.

### Scenario: Multiple sections
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:95` — "**N sections** → N issue groupings, one per section". `## Dependencies` exclusion at `read-change/SKILL.md:82`.
**Interpolated; no direct test.**

### Scenario: No section headings
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:96` — "**No `##` headings** → `read-change` returns a single section ... that becomes one issue grouping containing all tasks". Backing parse at `read-change/SKILL.md:96` ("If `tasks.md` has no `##` headings at all, the whole file is one implicit section").
**Interpolated; no direct test.**

---

## Requirement: Swarm path issue matching and filing

**Sources**
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:100-137` — step 5 "Match or file one issue per section": match via `gh issue list --label "opsx-change:<name>"` grepping each body for `<!-- opsx-section: <section-id> -->`; file via `gh issue create --label "opsx-change:<name>"` with the marker + task checklist.

### Scenario: Matching issue exists
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:104-111` — "the section is matched when its body contains `<!-- opsx-section: <section-id> -->`. Reuse the matched issue number — do **not** file a duplicate."
**Interpolated; no direct test.**

### Scenario: No matching issue
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:113-135` — "When no open issue matches a section, create a new one"; body starts with the marker, inlines tasks as `- [ ]`, applies the `opsx-change:<name>` label at creation via `gh issue create`.
**Interpolated; no direct test.**

---

## Requirement: Swarm path dependency wiring from dual sources

**Sources**
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:139-151` — step 6 "Wire blocked-by edges": "Use the **union of `inlineEdges` and `blockEdges`** ... deduplicated", wired via GitHub's native issue-dependencies API.
- `plugins/opsx-bridge/skills/read-change/SKILL.md:98-128` — steps 5–7: parse inline `<!-- depends: -->` markers, parse the `## Dependencies` block, union edges and detect cycles.

### Scenario: Inline depends marker
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:98-100` — step 5 "Parse inline depends markers": each `<!-- depends: <section-id> -->` yields `{from: <this section-id>, to: <referenced section-id>}`.
**Interpolated; no direct test.**

### Scenario: Explicit Dependencies block
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:102-104` — step 6 "Parse the Dependencies block": each `<Name B> blocked by <Name A>` line emits `{from: slug(B), to: slug(A)}`.
**Interpolated; no direct test.**

### Scenario: Inline and block both present
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:115-117` — step 7 "Merge edges and detect cycles": "Union `inlineEdges` and `blockEdges`, deduplicating identical `{from,to}` pairs." Consumed at `apply-via-swarm/SKILL.md:141` ("union ... deduplicated").
**Interpolated; no direct test.**

### Scenario: Cycle detected
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:117-128` — step 7: on a back-edge "Refuse — do not emit a payload" (exit non-zero, cycle on stderr). Surfaced by the swarm path at `apply-via-swarm/SKILL.md:52` ("Surface its stderr message verbatim and refuse to dispatch").
**Interpolated; no direct test.**

---

## Requirement: Swarm path topological dispatch

**Sources**
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:153-176` — step 7 "Compute topological order" + step 8 "Linearize the order, then dispatch to swarm-plus": topo-sort the union edge set, linearize, dispatch via `Skill({skill: "swarmkit:swarm-plus", args: "<n1> <n2> ... --base <BASE>"})`.

### Scenario: Issues in dependency order
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:163-168` — "Compose the ordered issue numbers as a space-separated list and dispatch via the Skill tool" passing the issue numbers in topological order.
**Interpolated; no direct test.**

---

## Requirement: Post-completion tasks.md reconciliation

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:146-160` — step 7 "Post-completion reconciliation": match merged PRs via `gh pr list --search "label:opsx-change:<name> is:merged"`, mark completed sections `[x]`, all-complete vs partial-completion branches.
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:178-192` — step 9 "Post-completion reconciliation": "Identical shape to `apply-via-squad` step 7", same all-complete vs partial branches.

### Scenario: All sections complete
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:157` — "**All sections complete** ... mark all tasks `[x]` and suggest `/opsx:archive <name>`." Mirror at `apply-via-swarm/SKILL.md:189`.
**Interpolated; no direct test.**

### Scenario: Partial completion
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:158` — "**Partial completion** ... mark **only** the completed sections' tasks `[x]`, leave incomplete sections untouched, and report which sections remain." Mirror at `apply-via-swarm/SKILL.md:190`.
**Interpolated; no direct test.**

---

## Requirement: Failure surfacing without retry

**Sources**
- `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:162-164` — step 8 "Failure surfacing — no retry": squad-member failure surfaces member name + current task, never mutates `tasks.md` for that section, "never auto-retries".
- `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:194-196` — step 10 "Failure surfacing — no retry": closed/stalled PR surfaces the issue number, never mutates `tasks.md`, re-invocation only re-dispatches sections without a matching merged PR.

### Scenario: Squad member fails verify
**Source:** `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md:164` — "If a squad member fails its verify gate or stops responding, surface the member name and its current task, and **do not** mutate `tasks.md` for that section ... never auto-retries".
**Interpolated; no direct test.**

### Scenario: Swarm worker fails
**Source:** `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md:196` — "If a per-issue worker's PR is closed without merge or stalls, surface the issue number and **do not** mutate `tasks.md` ... only sections without a matching merged PR get re-dispatched."
**Interpolated; no direct test.**

---

## Requirement: read-change internal sub-skill

**Sources**
- `plugins/opsx-bridge/skills/read-change/SKILL.md:1-10` — frontmatter (`name` + `description` only, "Not user-facing.") and the Tier-4 internal-component intro: "the single structured representation both dispatch paths consume."
- `plugins/opsx-bridge/skills/read-change/SKILL.md:130-154` — step 8 "Emit the payload": `jq -n` assembling `changeName`, `schemaName`, `capabilities`, `tasksBySection`, `inlineEdges`, `blockEdges`, `applyReady`, `applyRequires`.

### Scenario: Parsed change structure
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:144-153` — the emitted object `{ changeName, schemaName, capabilities, tasksBySection, inlineEdges, blockEdges, applyReady, applyRequires }` (matches the Output table at `:20-29`).
**Interpolated; no direct test.**

### Scenario: Internal-only visibility
**Source:** `plugins/opsx-bridge/skills/read-change/SKILL.md:10` — "There is **no top-level command** for this skill ... The frontmatter declares `name` + `description` only — no `triggers`, so the harness registers no `/opsx-bridge:read-change` command."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

Every scenario in this spec is **interpolated** from skill-document prose and bash
snippets — these are instruction-style SKILL.md files, not executable code with a test
suite, so no scenario is backed by a direct automated test. The numbered items below are
the human reviewer's checklist:

1. **Change discovery** — directory existence is enforced inside `read-change`
   (`read-change/SKILL.md:40-42`); both dispatch skills consume that failure and list
   available changes. No standalone test of the "available changes" listing path.
2. **Apply-readiness** — `read-change` *reports* `applyReady`/`applyRequires`
   (`read-change/SKILL.md:50-53`); enforcement (refuse + suggest `/opsx:propose`) lives
   in both dispatch skills' step 1. The reporting/enforcing split is by-design.
3. **Base resolution** — the three-step precedence is duplicated verbatim across both
   dispatch skills (squad step 2 / swarm step 2) by intent; verify they stay in sync.
4. **Squad capability derivation** — `min(N,4)` with `N==0 → 1` is the only place builder
   count is computed; `--profile` short-circuits it.
5. **Swarm dependency union + cycle detection** — parsing/union/cycle-check live in
   `read-change` (steps 5–7); the swarm path consumes the resolved edges and surfaces the
   cycle refusal. Verify the swarm path does not re-derive edges.
6. **Reconciliation & failure surfacing** — both are shared verbatim across the two
   dispatch skills; the "never mutate tasks.md for failed/incomplete sections" invariant
   (D7) is the load-bearing claim to re-check after any edit.
