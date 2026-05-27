---
name: apply-via-swarm
description: Dispatch an OpenSpec change to a swarmkit swarm. Reads openspec/changes/<name>/, groups tasks.md by ## section, files or reuses one GitHub issue per section (labelled opsx-change:<name> with an <!-- opsx-section: --> marker), wires blocked-by edges from the change's merged dependency set, and invokes /swarmkit:swarm-plus with the issue numbers in topological order. Reconciles tasks.md after the per-issue PRs land.
triggers:
  - "/opsx-bridge:apply-via-swarm"
  - "apply via swarm"
  - "apply change via swarm"
  - "dispatch change to swarm"
  - "swarm a change"
allowed-tools: Bash, Read, Edit, Skill
---

# Apply via Swarm

Bridge a single OpenSpec change to a `/swarmkit:swarm-plus` run. The skill reads `openspec/changes/<name>/`, groups `tasks.md` into one GitHub issue per `##` section (the granularity swarm dispatches on — see D2), wires blocked-by edges between those issues from the change's merged dependency set, and hands the ordered issue numbers to `/swarmkit:swarm-plus`. After the per-issue PRs land, it reconciles completed sections back into `tasks.md` so `/opsx:archive` works.

The bridge is **additive** — it calls `swarm-plus` as a black box through its public flag surface and never modifies swarmkit, opsx, or the change proposal. It is the sibling of `apply-via-squad`; the two share base-branch resolution, apply-readiness preflight, and post-completion reconciliation verbatim so they stay consistent.

## Input

`$ARGUMENTS` — the change name (positional) plus optional flags.

| Argument | Default | Effect |
|----------|---------|--------|
| `<change-name>` | required | Directory under `openspec/changes/`. Resolved by `read-change`. |
| `--base <branch>` | resolved | Override the base branch the section-issue PRs target. See base resolution below. |

Swarm-plus knobs (`--model`, `--worker-model`, `--reviewer-model`, `--review-only`) are not re-declared here; pass-through is out of scope for the bridge — the operator runs `/swarmkit:swarm-plus` directly if they want those.

## Process

### 1. Preflight — read and validate the change

Invoke the internal `read-change` sub-skill for the named change. Consume its documented JSON output contract; do not re-parse the change directory here. The fields this skill uses:

- `tasksBySection` — section-id → task list. Drives section grouping (step 4).
- `inlineEdges` + `blockEdges` — the two dependency sources. **Union and dedupe them** to get the edge set this skill wires (step 6). read-change has already resolved each `## Dependencies` operand to a real section-id and run a cycle check on the union — consume its resolved `{from, to}` pairs; do **not** re-derive section-ids or re-slug the operands yourself.
- `applyReady` / `applyRequires` — apply-readiness (this step).

```
Skill({skill: "opsx-bridge:read-change", args: "<change-name>"})
```

**Change not found.** `read-change` exits non-zero with a stderr message when `openspec/changes/<name>/` does not exist. On that failure, refuse to dispatch and list available changes so the operator can correct the name:

```bash
openspec list --json | jq -r '.[].name'
```

Report: `apply-via-swarm: no change "<name>". Available: <list>.`

**Cycle in the dependency graph.** `read-change` refuses (non-zero, nothing on stdout) when the merged edge set has a cycle. Surface its stderr message verbatim and refuse to dispatch — a cyclic graph has no topological order (spec scenario "Cycle detected"). Do not attempt to break the cycle.

**Apply-readiness.** Validate the change is apply-ready before dispatching. The CLI is the source of truth:

```bash
STATUS=$(openspec status --change "<name>" --json)
```

Every artifact named in `applyRequires` must have `status: "done"`. Equivalently, `read-change`'s `applyReady` field is `true`. If any required artifact is not `done`:

- Refuse to dispatch.
- Report which `applyRequires` artifacts are incomplete (name + current status).
- Suggest completing them: `Run /opsx:propose <name> to finish the outstanding artifacts, then re-run apply-via-swarm.`

This mirrors the spec's "Apply-readiness unsatisfied" scenario — the bridge proceeds only when readiness is satisfied.

### 2. Resolve the base branch

Identical to `apply-via-squad` step 2 — shared logic, do not diverge. Never hardcode `develop` or `main`. Resolve `$BASE` in order, stopping at the first non-empty result (D5):

1. `--base <branch>` flag (per-invocation override).
2. `git config claude.flowkit.prBase` (operator session pin).
3. `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub default).

```bash
BASE="${BASE_FLAG:-$(git config claude.flowkit.prBase 2>/dev/null)}"
[ -n "$BASE" ] || BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
```

The resolved `$BASE` is passed through to `swarm-plus` via `--base <BASE>` (step 8). Each independent section-issue PR targets `$BASE`; dependent ones stack onto their predecessor's branch and retarget to `$BASE` on merge (swarm's own model).

### 3. Resolve the repo owner/name

GitHub's dependency API and issue filing need the `{owner}/{repo}` slug. Resolve it once:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 4. Group tasks into section-issues

Consume `read-change`'s `tasksBySection` map — one section maps to one GitHub issue (D2). The map is keyed by section-id and preserves heading order.

- **N sections** → N issue groupings, one per section (spec "Multiple sections").
- **No `##` headings** → `read-change` returns a single section keyed on the change-name slug; that becomes one issue grouping containing all tasks (spec "No section headings", D8 no-specs note).

Each grouping carries: the section-id (for the marker), the section heading text (for the issue title), and the task list (for the body checklist).

### 5. Match or file one issue per section

For each section, find an existing issue or file a new one. Build the section-id → issue-number map as you go (needed for dependency wiring and topological dispatch).

**Match.** List issues carrying the change label and grep each body for the section marker (spec "Matching issue exists"):

```bash
gh issue list --label "opsx-change:<name>" --state open --json number,body \
  | jq -r '.[] | "\(.number)\t\(.body)"'
```

For each candidate, the section is matched when its body contains `<!-- opsx-section: <section-id> -->`. Reuse the matched issue number — do **not** file a duplicate.

**File.** When no open issue matches a section, create a new one (spec "No matching issue", D2 step 3). The body MUST:

- Start with the marker `<!-- opsx-section: <section-id> -->` on its own line.
- Inline the section's tasks as a `- [ ]` checklist (the work the per-issue agent resolves).
- Carry a footer pointing the agent at the change directory so it reads `proposal.md` + `design.md` for orientation (D4 swarm-path briefing).

Apply the `opsx-change:<name>` label at creation:

```bash
gh issue create \
  --title "[<change-name> §<section>] <heading text>" \
  --label "opsx-change:<name>" \
  --body "$(cat <<'EOF'
<!-- opsx-section: <section-id> -->

<section task checklist as - [ ] items>

## Context

Part of OpenSpec change `<change-name>`. Read `openspec/changes/<change-name>/proposal.md` and `design.md` for the full design before implementing.
EOF
)"
```

> **Live example.** Issue #992 (the one resolved by this very section of the opsx-bridge change) is exactly this shape: label `opsx-change:opsx-bridge`, a leading `<!-- opsx-section: apply-via-swarm -->` marker, tasks inlined as a checklist, and a context footer pointing at the change directory. Preserve this shape when filing.

### 6. Wire blocked-by edges

Use the **union of `inlineEdges` and `blockEdges`** from `read-change`, deduplicated (spec "Inline and block both present"). Each edge is `{from: dependent-section, to: blocking-section}` keyed on section-ids — read-change already resolved the `## Dependencies` operands to real section-ids and cycle-checked the union, so wire them as-is.

Map both endpoints through the section-id → issue-number map (step 5), then resolve each issue number to its GitHub node id and wire the blocked-by edge via GitHub's native issue-dependencies API. Use `-F` for the integer id field so it is sent as a number, not a string:

```bash
# blocked = issue number of edge.from (the dependent); blocking = issue number of edge.to
blocking_id=$(gh api "repos/$REPO/issues/$blocking" -q .id)
gh api "repos/$REPO/issues/$blocked/dependencies/blocked_by" -X POST -F issue_id="$blocking_id"
```

This is the same `blockedBy` connection swarm reads in its dependency-graph step — wiring it here means swarm-plus picks the edges up natively without re-parsing issue bodies. An edge whose endpoint has no filed issue (e.g. an unresolved dangling reference read-change reported on stderr) is skipped with a warning — do not invent an issue for it.

### 7. Compute topological order

Build the DAG from the same union edge set (edge `from → to` means *from* is blocked by *to*) over the section-issue nodes and topologically sort it so every blocking issue precedes the issues it blocks. read-change has already guaranteed the graph is acyclic, so a valid order always exists (spec "Issues in dependency order").

### 8. Linearize the order, then dispatch to swarm-plus

> **Design note — diamond graphs must be linearized.** swarm's stacked-PR model is **single-parent**: each dependent agent branches from exactly *one* parent's branch tip (`git checkout -b worktree-agent-<this> origin/worktree-agent-<dependency>`) and its PR targets that one parent. But an OpenSpec change's dependency graph can be a **diamond** — a section depending on two others (a fan-in). swarm cannot express two parents for one branch. So when the graph is not a simple chain, the bridge MUST **linearize** the topological order into a single stack before handing issue numbers to swarm-plus: emit the issues in topological order as one linear sequence, so each downstream issue stacks on the single issue immediately before it. This is correctness-preserving when the fan-in sections touch disjoint files (the common case — sections map to distinct capabilities/areas) because a linear stack still has every upstream section's commits present in each downstream worktree; it only over-constrains ordering, never under-constrains it.
>
> This was discovered dogfooding this very plugin: the opsx-bridge change graph had #993 (section 5, the capability files) depending on **both** #991 (apply-via-squad) and #992 (apply-via-swarm) — a diamond fan-in. Linearizing the topo order into `#990 → #991 → #992 → #993` lets swarm chain each as a single-parent stack while still respecting every blocked-by edge.

Compose the ordered issue numbers as a space-separated list and dispatch via the Skill tool, passing the resolved base through:

```
Skill({skill: "swarmkit:swarm-plus",
       args: "<n1> <n2> <n3> ... --base <BASE>"})
```

Show the operator the constructed argument string before dispatching. Example (this very change — five section-issues after linearization, targeting the resolved base):

```
/swarmkit:swarm-plus 990 991 992 993 994 --base develop
```

swarm-plus owns the rest: per-issue worktree provisioning, the stacked-PR chain, the automatic review/fix pass per PR, and leaving the PRs open for human merge. The bridge does not micromanage the workers.

### 9. Post-completion reconciliation

Identical shape to `apply-via-squad` step 7 — shared logic. After the per-issue PRs land, reconcile `tasks.md`. Detect completion by matching merged PRs for issues labeled `opsx-change:<name>`:

```bash
gh pr list --search "label:opsx-change:<name> is:merged" --state merged \
  --json number,title,body
```

For each `tasks.md` section whose corresponding section-issue has a matching merged PR, mark every `- [ ]` item in that section `- [x]` via `Edit`. Then:

- **All sections complete** — every section-issue has a matching merged PR: mark all tasks `[x]` and suggest `/opsx:archive <name>`. Confirm via `openspec status --change <name> --json` (`isComplete: true`).
- **Partial completion** — only some section-issues have merged PRs: mark **only** the completed sections' tasks `[x]`, leave incomplete sections untouched, and report which sections remain.

**Never mutate `tasks.md` for failed or incomplete sections** (D7). The operator decides whether to re-run for the unfinished work.

### 10. Failure surfacing — no retry

If a per-issue worker's PR is closed without merge or stalls, surface the issue number and **do not** mutate `tasks.md` for that section (D7, spec "Swarm worker fails"). The bridge **never auto-retries**. Because step 5 reuses any existing matching issue and reconciliation keys on merged PRs, the operator can simply re-invoke `apply-via-swarm <name>`: matched issues with merged PRs are already reconciled, and only sections without a matching merged PR get re-dispatched.

## Notes

- **read-change is the parser.** This skill consumes read-change's `tasksBySection` and the union of its `inlineEdges` + `blockEdges`; it does not re-implement section parsing, operand resolution, or cycle detection. Apply-readiness is *reported* by read-change and *enforced* here.
- **swarm-plus is a black box.** apply-via-swarm files/matches issues, wires native blocked-by edges, linearizes the order, and dispatches issue numbers + `--base`. It never inspects or modifies swarmkit internals.
- **Issues are the contract, tasks.md is authoritative.** `tasks.md` decides *which* sections exist; the section-issue body is (re)generated from it. Issue reuse is keyed on the `<!-- opsx-section: -->` marker so re-invocations are idempotent against the GH board.

## Composition

| Calls | Why |
|-------|-----|
| `opsx-bridge:read-change` | Parse the change into tasks-by-section + merged dependency edges + apply-readiness (preflight). |
| `swarmkit:swarm-plus` | Dispatch the ordered section-issues as a reviewed stacked-PR chain. |
