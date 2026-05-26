## 1. Plugin Scaffolding

- [x] 1.1 Create `plugins/opsx-bridge/plugin.json` with version `0.1.0`, name `opsx-bridge`, description, and skill manifest entries for `apply-via-squad`, `apply-via-swarm`, and `read-change`
- [x] 1.2 Create directory structure: `plugins/opsx-bridge/skills/{apply-via-squad,apply-via-swarm,read-change}/`
- [x] 1.3 Add `plugins/opsx-bridge/README.md` with overview, install instructions, and a "which dispatcher to pick" decision table mirroring the design doc
- [x] 1.4 Register `opsx-bridge` in the marketplace manifest (`marketplaces/smallorbit-plugins.json` or equivalent) so it can be installed

## 2. Internal Sub-Skill: read-change

- [ ] 2.1 Author `plugins/opsx-bridge/skills/read-change/SKILL.md` covering: input (change name), output (structured payload per spec Requirement: read-change internal sub-skill), invocation via `openspec status` / `openspec instructions` CLI calls
- [ ] 2.2 Add parsing logic for `## Capabilities` section of proposal.md (extract New + Modified capability names as unique list)
- [ ] 2.3 Add parsing logic for tasks.md sections (group `- [ ]` items by parent `##` heading, compute stable section-id via slug)
- [ ] 2.4 Add parsing logic for inline `<!-- depends: <section-id> -->` markers in section headers
- [ ] 2.5 Add parsing logic for `## Dependencies` block (lines like `Section B blocked by Section A`)
- [ ] 2.6 Add cycle detection on merged dependency edges; refuse with error when cycle present
- [ ] 2.7 Verify SKILL.md frontmatter declares no user-facing slash command (no `name:` that maps to a top-level command file)

## 3. apply-via-squad Skill

- [ ] 3.1 Author `plugins/opsx-bridge/skills/apply-via-squad/SKILL.md` covering: input (change name + flags), preflight checks, dispatch invocation, post-completion reconciliation
- [ ] 3.2 Implement preflight: invoke `read-change` and verify apply-readiness via `openspec status --change <name> --json`; refuse if `applyRequires` unsatisfied
- [ ] 3.3 Implement base branch resolution chain: `--base` flag → `claude.flowkit.prBase` → `gh repo view --json defaultBranchRef`
- [ ] 3.4 Implement profile derivation: capability count from read-change output, cap at 4, default to 1 when capability count is 0
- [ ] 3.5 Implement `--profile <name>` override path: pass through to spawn-team, skip derivation
- [ ] 3.6 Implement brief composition: include `--brief @proposal.md` and (if present) `--brief @design.md`
- [ ] 3.7 Implement epic flag handling: `--epic <change-name>` by default; suppress on `--no-epic`
- [ ] 3.8 Invoke `/squadkit:spawn-team` with the composed arguments
- [ ] 3.9 Implement post-completion reconciliation: poll merged-PR state for issues labeled `opsx-change:<name>`; update tasks.md checkboxes; suggest `/opsx:archive` when all sections complete

## 4. apply-via-swarm Skill

- [ ] 4.1 Author `plugins/opsx-bridge/skills/apply-via-swarm/SKILL.md` covering: input (change name + flags), section-to-issue mapping, dispatch invocation, post-completion reconciliation
- [ ] 4.2 Implement preflight: invoke `read-change` and verify apply-readiness; refuse if `applyRequires` unsatisfied
- [ ] 4.3 Implement base branch resolution chain (shared logic with apply-via-squad)
- [ ] 4.4 Implement issue matching: `gh issue list --label "opsx-change:<name>"` → grep body for `<!-- opsx-section: <section-id> -->` → reuse if match
- [ ] 4.5 Implement issue filing: when no match, create new issue with section tasks inlined, apply `opsx-change:<name>` label, embed `<!-- opsx-section: <section-id> -->` marker in body
- [ ] 4.6 Wire blocked-by edges using GitHub issue dependencies (via `gh api` or comment-based pattern) per the dependency set returned by read-change
- [ ] 4.7 Compute topological order of issues from dependency graph
- [ ] 4.8 Invoke `/swarmkit:swarm-plus` with the ordered issue numbers
- [ ] 4.9 Implement post-completion reconciliation: same shape as apply-via-squad's reconciliation (poll merged PRs, update tasks.md, suggest archive)

## 5. OpenSpec Capability Files

- [ ] 5.1 Create `plugins/opsx-bridge/openspec/specs/opsx-bridge/spec.md` (baseline spec — copy the requirements from `openspec/changes/opsx-bridge/specs/opsx-bridge/spec.md` minus the `## ADDED Requirements` delta header)
- [ ] 5.2 Create `plugins/opsx-bridge/openspec/specs/opsx-bridge/REFERENCES.md` citing each requirement and scenario back to the SKILL.md file:line that implements it
- [ ] 5.3 Run `/spec-baseline` audit agent on the bridge plugin to verify citations match implementation

## 6. Documentation and Integration

- [ ] 6.1 Add a "Spec-driven workflow with opsx-bridge" section to the repo's root README, linking to the plugin README and explaining when to pick squad vs swarm
- [ ] 6.2 Update `openspec/README.md` to mention opsx-bridge as the multi-agent dispatch path for `/opsx:apply` (referencing `apply-via-squad` and `apply-via-swarm`)
- [ ] 6.3 Add an entry in CLAUDE.md noting opsx-bridge in the canonical bubble-free release sequence (optional integration with the existing `merge-stack → verify → ship-epic → ship` chain)

## 7. Validation

- [ ] 7.1 Run `openspec validate opsx-bridge --strict` and confirm clean
- [ ] 7.2 Smoke-test `apply-via-squad` against a tiny synthetic change in a worktree (no real dispatch — verify preflight + arg composition only)
- [ ] 7.3 Smoke-test `apply-via-swarm` against a tiny synthetic change (verify section parsing + issue matching dry-run)
- [ ] 7.4 Run `/tighten-to-spec` against both SKILL.md files to surface bloat or non-compliance
- [ ] 7.5 Bump `plugins/opsx-bridge/plugin.json` from `0.1.0` to first release version and tag

## Dependencies

Section 3 (apply-via-squad) blocked by Section 2 (read-change).
Section 4 (apply-via-swarm) blocked by Section 2 (read-change).
Section 5 (OpenSpec capability files) blocked by Section 3 and Section 4.
Section 6 (Documentation) blocked by Section 5.
Section 7 (Validation) blocked by Section 6.
