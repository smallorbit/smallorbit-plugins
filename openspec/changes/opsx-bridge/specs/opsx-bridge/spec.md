## ADDED Requirements

### Requirement: Change discovery by name

The bridge SHALL resolve a change directory by name from `openspec/changes/<name>/`.

#### Scenario: Change name matches existing directory

- **WHEN** the operator invokes `/opsx-bridge:apply-via-squad <name>` or `/opsx-bridge:apply-via-swarm <name>` and `openspec/changes/<name>/` exists
- **THEN** the bridge proceeds with that change as the dispatch target

#### Scenario: Change name does not match

- **WHEN** the operator invokes a bridge skill with a name that does not match any `openspec/changes/<name>/` directory
- **THEN** the bridge SHALL refuse to dispatch and report the missing change with a list of available changes (via `openspec list --json`)

### Requirement: Apply-readiness validation

The bridge SHALL validate that a change is apply-ready before invoking any dispatcher.

#### Scenario: Apply-readiness satisfied

- **WHEN** `openspec status --change <name> --json` reports all `applyRequires` artifacts have `status: "done"`
- **THEN** the bridge proceeds to dispatch

#### Scenario: Apply-readiness unsatisfied

- **WHEN** one or more `applyRequires` artifacts have status other than `"done"`
- **THEN** the bridge SHALL refuse to dispatch and report which artifacts are incomplete, suggesting `/opsx:propose <name>` to complete them

### Requirement: Base branch resolution

The bridge SHALL resolve the target base branch via a documented precedence chain and never hardcode a specific branch name.

#### Scenario: Explicit --base flag

- **WHEN** the operator passes `--base <branch>` on the bridge invocation
- **THEN** the bridge uses `<branch>` as the base

#### Scenario: Session-pinned base

- **WHEN** no `--base` flag is provided and `git config claude.flowkit.prBase` returns a value
- **THEN** the bridge uses the pinned value as the base

#### Scenario: GitHub default fallback

- **WHEN** no `--base` flag is provided and no session pin is set
- **THEN** the bridge resolves the base via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`

### Requirement: Squad path builder derivation from capabilities

The `apply-via-squad` skill SHALL derive default builder count from the proposal's `## Capabilities` section, treating capabilities as the universal unit of work.

#### Scenario: Multiple capabilities

- **WHEN** the proposal lists N unique capabilities (New + Modified combined) and N <= 4
- **THEN** the derived profile includes N builders

#### Scenario: Capability count exceeds cap

- **WHEN** the proposal lists more than 4 unique capabilities
- **THEN** the derived profile caps the builder count at 4

#### Scenario: No capabilities (no-specs change)

- **WHEN** the proposal lists zero capabilities (e.g. refactor change with proposal.md + tasks.md only)
- **THEN** the derived profile defaults to 1 builder, and the bridge proceeds without refusing

#### Scenario: Explicit profile override

- **WHEN** the operator passes `--profile <name>`
- **THEN** the bridge skips capability-based derivation and passes `--profile <name>` through to `/squadkit:spawn-team`

### Requirement: Squad path brief passing

The `apply-via-squad` skill SHALL pass proposal and design documents as briefs to `/squadkit:spawn-team`.

#### Scenario: Proposal and design both present

- **WHEN** both `proposal.md` and `design.md` exist in the change directory
- **THEN** the bridge invokes spawn-team with `--brief @<proposal.md> --brief @<design.md>`

#### Scenario: Proposal only

- **WHEN** only `proposal.md` exists (design.md absent or empty)
- **THEN** the bridge invokes spawn-team with `--brief @<proposal.md>` only

### Requirement: Squad path epic branch handling

The `apply-via-squad` skill SHALL invoke `/squadkit:spawn-team` with an epic flag by default.

#### Scenario: Default epic mode

- **WHEN** the bridge invokes spawn-team without `--no-epic`
- **THEN** the invocation includes `--epic <change-name>` so the crew works on `feature/<change-name>-<parent-issue>` cut from the resolved base

#### Scenario: Operator disables epic

- **WHEN** the operator passes `--no-epic` to the bridge
- **THEN** the bridge invokes spawn-team without the `--epic` flag and the squad commits directly against the resolved base branch

### Requirement: Swarm path section grouping

The `apply-via-swarm` skill SHALL group `tasks.md` items by their parent `##` heading and map each section to one GitHub issue.

#### Scenario: Multiple sections

- **WHEN** `tasks.md` contains N `##` sections (excluding any `## Dependencies` block)
- **THEN** the bridge produces N issue groupings, one per section

#### Scenario: No section headings

- **WHEN** `tasks.md` contains no `##` headings
- **THEN** the bridge produces a single issue grouping containing all tasks

### Requirement: Swarm path issue matching and filing

The `apply-via-swarm` skill SHALL reuse existing GitHub issues that match a section, or file new ones when no match exists.

#### Scenario: Matching issue exists

- **WHEN** an open issue carries the label `opsx-change:<name>` and its body contains the marker `<!-- opsx-section: <section-id> -->`
- **THEN** the bridge reuses that issue rather than filing a new one

#### Scenario: No matching issue

- **WHEN** no open issue matches the label + marker for a section
- **THEN** the bridge files a new GitHub issue with the section's tasks inlined as a checklist, applies the `opsx-change:<name>` label, and includes the `<!-- opsx-section: <section-id> -->` marker in the body

### Requirement: Swarm path dependency wiring from dual sources

The `apply-via-swarm` skill SHALL compute blocked-by edges between section-issues from two sources, merged as a union.

#### Scenario: Inline depends marker

- **WHEN** a section header includes `<!-- depends: <other-section-id> -->`
- **THEN** the bridge wires a blocked-by edge from this section's issue to the referenced section's issue

#### Scenario: Explicit Dependencies block

- **WHEN** `tasks.md` includes a `## Dependencies` block with lines like `Section B blocked by Section A`
- **THEN** the bridge wires the corresponding blocked-by edges

#### Scenario: Inline and block both present

- **WHEN** both sources specify edges for the same change
- **THEN** the bridge merges them as a union, deduplicating identical edges

#### Scenario: Cycle detected

- **WHEN** the computed edge set contains a cycle
- **THEN** the bridge SHALL refuse to dispatch and report the cycle

### Requirement: Swarm path topological dispatch

The `apply-via-swarm` skill SHALL invoke `/swarmkit:swarm-plus` with section-issues in topological dependency order.

#### Scenario: Issues in dependency order

- **WHEN** the bridge has resolved or filed all section-issues and computed a valid topological order
- **THEN** the invocation of `/swarmkit:swarm-plus` passes the issue numbers in that order

### Requirement: Post-completion tasks.md reconciliation

The bridge SHALL reconcile `tasks.md` checkbox state with merged PRs after dispatcher completion.

#### Scenario: All sections complete

- **WHEN** every section-issue has a corresponding merged PR (label-matched)
- **THEN** the bridge marks every task in `tasks.md` as `[x]` and suggests `/opsx:archive <name>`

#### Scenario: Partial completion

- **WHEN** some section-issues have merged PRs and others do not
- **THEN** the bridge marks only the completed sections' tasks as `[x]`, leaves incomplete sections unmodified, and reports which sections remain

### Requirement: Failure surfacing without retry

The bridge SHALL surface dispatcher failures without auto-retrying.

#### Scenario: Squad member fails verify

- **WHEN** a squad member fails its verify gate or does not respond to coordination messages
- **THEN** the bridge reports the member name and current task, and SHALL NOT mutate `tasks.md` for the failed section

#### Scenario: Swarm worker fails

- **WHEN** a swarm worker's PR is closed without merge or stalls
- **THEN** the bridge reports the issue number, and SHALL NOT mutate `tasks.md` for that section. The operator may re-invoke `apply-via-swarm`, and the bridge will only dispatch agents for issues without matching merged PRs.

### Requirement: read-change internal sub-skill

The `opsx-bridge` plugin SHALL include an internal sub-skill `read-change` that parses `openspec/changes/<name>/` into a structured representation consumed by `apply-via-squad` and `apply-via-swarm`.

#### Scenario: Parsed change structure

- **WHEN** `read-change` is invoked with a change name
- **THEN** it returns a structured payload containing: change name, schema name, proposal capabilities (list of strings), tasks-by-section (map of section-id → task list), inline dependency markers (list of {from, to}), explicit Dependencies block edges (list of {from, to}), and apply-readiness status

#### Scenario: Internal-only visibility

- **WHEN** an operator types `/opsx-bridge:read-change <name>` directly
- **THEN** the skill is not advertised as a user-facing slash command (it lives under `skills/read-change/SKILL.md` without a corresponding top-level command file)
