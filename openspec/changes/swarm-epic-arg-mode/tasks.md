# tasks

Implementation decomposition for making a single epic argument enable epic mode in `swarm`. Single coordinated change.

## 1. Resolution logic

- [ ] Update `plugins/swarmkit/skills/swarm/SKILL.md` Epic Mode Resolution: for the one-shot single-argument case, consult epic membership (via `gather_issues.sh` `epics_expanded` / `is_epic`) before finalizing. A single argument that is an epic expanding to ≥2 wired children resolves `EPIC_MODE=on`; a standalone non-epic issue (or an epic with <2 wired children, or `epics_unwired`) stays off. Preserve `--base` / `--no-epic` as forcing off.
- [ ] Ensure the "compute before any setup work" guidance still holds for all cases except the single-arg probe, and document that gather runs before the cut in that one case.
- [ ] Reuse the existing slug-derivation rule (epic, or lowest-numbered child, via `gh issue view`) for the cut.

## 2. Docs + spec

- [ ] Update `plugins/swarmkit/METHODOLOGY.md` to describe the single-epic-arg → epic-mode behavior alongside the existing multi-issue epic example.
- [ ] Update `plugins/swarmkit/README.md` if its flag/mode description states the single-issue-one-shot → flat rule.
- [ ] Update the baseline spec `openspec/specs/swarmkit-swarm/spec.md` "Epic mode resolution" requirement (this change's delta is the source of truth).

## 3. Tests

- [ ] Extend `plugins/swarmkit/skills/swarm/scripts/test.sh` (or the gather test) with a single-epic-arg fixture asserting `epics_expanded` is populated and `is_epic` is true for the argument.
- [ ] Add a standalone-issue fixture asserting it is NOT treated as an epic (regression guard for the off path).

## 4. Dependency note

- [ ] The `skill-evals` change's L3 EPIC_MODE eval (`evals/l3/swarm/epic-mode-single-arg`) asserts this behavior — coordinate so the eval lands after this change.
