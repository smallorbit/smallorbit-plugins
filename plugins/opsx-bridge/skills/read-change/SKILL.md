---
name: read-change
description: Parse an OpenSpec change directory into a structured payload (capabilities, tasks-by-section, dependency edges, apply-readiness). Internal sub-skill used by opsx-bridge:apply-via-squad and apply-via-swarm. Not user-facing.
---

# read-change

Tier 4 sub-skill (internal component, not user-facing). It parses `openspec/changes/<name>/` into the single structured representation both dispatch paths consume. `apply-via-squad` reads the capabilities to size the crew; `apply-via-swarm` reads the tasks-by-section map and the merged dependency edges to file and order issues.

There is **no top-level command** for this skill. It is invoked only by its sibling bridge skills (or directly during development), never advertised to operators. The frontmatter declares `name` + `description` only — no `triggers`, so the harness registers no `/opsx-bridge:read-change` command.

## Input

A single change name (the directory under `openspec/changes/`). No flags.

## Output

A bare JSON payload on stdout with these fields:

| Field | Type | Source |
|-------|------|--------|
| `changeName` | string | the input name |
| `schemaName` | string | `openspec status --json` → `.schemaName` |
| `capabilities` | string[] | unique New + Modified capability names from `proposal.md` (§2.2) |
| `tasksBySection` | object | section-id → array of task strings (§2.3) |
| `inlineEdges` | {from,to}[] | inline `<!-- depends: -->` markers (§2.4) |
| `blockEdges` | {from,to}[] | `## Dependencies` block lines (§2.5) |
| `applyReady` | boolean | `openspec status --json` → `.isComplete` |
| `applyRequires` | string[] | `openspec status --json` → `.applyRequires` |

Section IDs are stable slugs of the `##` heading text. Edges are directional `blocked-by`: `{from: dependent-section, to: blocking-section}` means *from* is blocked by *to*.

On any cycle in the merged edge set, the skill emits nothing to stdout, writes the cycle to stderr, and exits non-zero (§2.6).

## Process

### 1. Resolve the change and validate it exists

```bash
NAME="$1"
CHANGE_DIR="openspec/changes/$NAME"
[ -d "$CHANGE_DIR" ] || { echo "read-change: no change directory openspec/changes/$NAME (run: openspec list --json)" >&2; exit 1; }
```

### 2. Read status (schema, apply-readiness)

The OpenSpec CLI is the source of truth for schema and apply-readiness — never re-derive these from the filesystem.

```bash
STATUS=$(openspec status --change "$NAME" --json) || { echo "read-change: openspec status failed for $NAME" >&2; exit 1; }
SCHEMA=$(jq -r '.schemaName' <<<"$STATUS")
APPLY_READY=$(jq -r '.isComplete' <<<"$STATUS")
APPLY_REQUIRES=$(jq -c '.applyRequires' <<<"$STATUS")
```

`openspec instructions apply --change <name> --json` is also available — it returns `contextFiles` (absolute paths to proposal/design/specs/tasks) and a parsed `tasks` array. Prefer it when you want the CLI's own task parse rather than re-reading `tasks.md`; the section grouping below still has to be done by this skill since the CLI returns a flat task list.

### 3. Parse capabilities from proposal.md (§2.2)

Extract the backtick-wrapped kebab-case identifiers from the bullet lists under `### New Capabilities` and `### Modified Capabilities` inside the `## Capabilities` section. Capability names look like `` `opsx-bridge` `` at the start of each bullet. De-duplicate (a name appearing under both New and Modified counts once). Skip the literal word `None`.

```bash
PROPOSAL="$CHANGE_DIR/proposal.md"
CAPS='[]'
if [ -f "$PROPOSAL" ]; then
  CAPS=$(awk '
    /^## Capabilities/ {incap=1; next}
    /^## / && incap {incap=0}
    incap && /^- `/ {
      line=$0
      sub(/^- `/, "", line); sub(/`.*/, "", line)
      if (line != "" && line != "None") print line
    }
  ' "$PROPOSAL" | awk '!seen[$0]++' | jq -R . | jq -s -c .)
fi
```

`### New Capabilities` and `### Modified Capabilities` are both `### ` (level-3) headings inside the `## Capabilities` (level-2) section, so the level-2 guard above keeps scanning across them and stops at the next `## `.

### 4. Parse tasks grouped by section (§2.3)

Group every `- [ ]` / `- [x]` item under its nearest preceding `##` heading. Compute the section-id by slugifying the heading text. **Exclude** a `## Dependencies` section — it carries edges, not tasks.

Slug rule: lowercase, replace each run of non-alphanumeric characters with a single hyphen, trim leading/trailing hyphens.

```bash
slug() { tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
```

When parsing a `##` heading, strip any trailing inline `<!-- ... -->` comment before slugifying (the heading "`## Foo <!-- depends: bar -->`" has section-id `foo`, not `foo-depends-bar`).

```bash
TASKS=$(TASKS_BY_SECTION_via_awk "$CHANGE_DIR/tasks.md")
```

Implement the grouping in `awk`: on each `## ` line, strip `<!-- ... -->`, slug the remainder, set the current section (skipping `dependencies`); on each `- [` line, append the item text (without the `- [ ] ` / `- [x] ` prefix) to the current section's list. Emit a JSON object of `section-id → [task, ...]`, preserving heading order. If `tasks.md` has no `##` headings at all, the whole file is one implicit section (matching the swarm path's "no section headings → single grouping" contract) — key it on the change name slug.

### 5. Parse inline depends markers (§2.4)

For each `## ` heading, scan its text for `<!-- depends: <section-id> -->`. Each marker yields an edge `{from: <this heading's section-id>, to: <referenced section-id>}`. A heading may carry more than one marker. The referenced id is used verbatim (it is already a section-id slug by convention) — but pass it through the same slug rule defensively.

### 6. Parse the Dependencies block (§2.5)

Read the `## Dependencies` section. Each non-empty line matches `<Name B> blocked by <Name A>` (case-insensitive on the connector). Map both human names back to section-ids by slugifying them, then emit `{from: slug(B), to: slug(A)}`. Also accept the inverse phrasing `<Name A> blocks <Name B>`, which yields the same `{from: slug(B), to: slug(A)}`.

**Resolve each operand to a real section-id**, do not blindly slug it. Block operands are written for humans (`Section 3 (apply-via-squad)`, `Section B`) and rarely slug to the exact heading slug — `Section 3 (apply-via-squad)` slugs to `section-3-apply-via-squad`, which is not the heading slug `3-apply-via-squad-skill`. Resolution rule, applied to each operand against the set of section-ids built in step 4:

1. Exact match of `slug(operand)` against a known section-id.
2. Else, if the operand contains a leading section number (`Section 3`, `3.`), match the section-id that starts with that number (`3-...`).
3. Else, if `slug(operand)` is a substring of exactly one section-id (or vice-versa), match that one.
4. Else, leave the operand unresolved and report it on stderr as a dangling dependency reference (do not silently drop it; an edge to a non-existent section is an authoring error worth surfacing).

This keeps the block tolerant of human phrasing while still emitting edges keyed on the same section-ids the rest of the payload uses. (Author convention: write Dependencies-block names so step 1 or step 2 resolves them — e.g. keep the leading `Section N`.)

### 7. Merge edges and detect cycles (§2.6)

Union `inlineEdges` and `blockEdges`, deduplicating identical `{from,to}` pairs. Build the directed graph (edge `from → to`) and run a DFS/topological check. If a back-edge is found, the change has a dependency cycle:

```bash
# pseudo: nodes = sections; edges = from -> to (from is blocked by to)
# if Kahn's algorithm cannot drain all nodes, a cycle remains.
if HAS_CYCLE; then
  echo "read-change: dependency cycle detected: $CYCLE_PATH (e.g. a -> b -> a). Fix the depends markers or ## Dependencies block in $CHANGE_DIR/tasks.md." >&2
  exit 1
fi
```

Name the offending nodes in the stderr message so the operator can find the bad marker. Refuse — do not emit a payload.

### 8. Emit the payload

Assemble with `jq -n` using `--arg` / `--argjson` so the output is always valid JSON. Never echo a hand-built JSON string.

```bash
jq -n \
  --arg name "$NAME" \
  --arg schema "$SCHEMA" \
  --argjson caps "$CAPS" \
  --argjson tasks "$TASKS" \
  --argjson inline "$INLINE_EDGES" \
  --argjson block "$BLOCK_EDGES" \
  --argjson ready "$APPLY_READY" \
  --argjson requires "$APPLY_REQUIRES" \
  '{
    changeName: $name,
    schemaName: $schema,
    capabilities: $caps,
    tasksBySection: $tasks,
    inlineEdges: $inline,
    blockEdges: $block,
    applyReady: $ready,
    applyRequires: $requires
  }'
```

## Worked example: this change itself

Run against `openspec/changes/opsx-bridge/` the skill produces:

- `capabilities`: `["opsx-bridge"]` (one New capability; Modified is `None`).
- `tasksBySection`: seven sections. The headings are numbered (`## 1. Plugin Scaffolding`, ...) so the slugs preserve the number prefix: `1-plugin-scaffolding`, `2-internal-sub-skill-read-change`, `3-apply-via-squad-skill`, `4-apply-via-swarm-skill`, `5-openspec-capability-files`, `6-documentation-and-integration`, `7-validation`. The `## Dependencies` section is excluded.
- `inlineEdges`: `[]` (this tasks.md uses no inline markers).
- `blockEdges`: the edges from the `## Dependencies` block. The block phrases them as `Section 3 (apply-via-squad) blocked by Section 2 (read-change)`; the step-6 leading-number resolution maps each operand onto its heading section-id, yielding e.g. `{from: "3-apply-via-squad-skill", to: "2-internal-sub-skill-read-change"}`, plus the four-edge fan-in for sections 5–7.
- `applyReady`: `true`, `applyRequires`: `["tasks"]`.

No cycle, so the payload is emitted.

## Notes for callers

- **Apply-readiness is reported, not enforced here.** This sub-skill surfaces `applyReady` / `applyRequires`; the calling bridge skill decides whether to refuse dispatch (per the spec's apply-readiness requirement).
- **Cycle detection is enforced here.** A cyclic dependency graph is structurally unusable for topological dispatch, so `read-change` refuses up front rather than handing a broken graph to `swarm-plus`.
- **Edges are returned split (inline vs block), not pre-merged.** Callers that only need the union should merge-and-dedupe; the split is preserved so a caller can report provenance if it wants. Cycle detection above runs on the union regardless.
