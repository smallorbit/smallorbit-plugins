# tasks

Implementation decomposition for the skill-evals strategy. Phased so the cheap, deterministic, high-ROI layers (L1, L2) land and gate first; LLM-in-loop layers (L3, L4) follow. Each phase is independently shippable.

## 1. L1 — Script unit tests (gate the tests that already exist)

- [ ] Add `scripts/run-skill-tests.sh`: discover every `plugins/*/skills/*/scripts/test.sh` (`find ... | while read`, never `for N in $(...)`), run each, fail on any non-zero exit, summarize pass/fail per skill.
- [ ] Add `.github/workflows/skills-ci.yml` with an L1 job that runs `scripts/run-skill-tests.sh` on PRs touching `plugins/**`. Mark it a required check.
- [ ] Backfill `test.sh` for script-backed skills that lack one (audit `plugins/*/skills/*/scripts/` for scripts without a sibling `test.sh`).
- [ ] Update `plugins/_shared/script-authoring.md`: `test.sh` is mandatory for any script-backed skill; reference the runner + CI gate.
- [ ] Update `CLAUDE.md` (Skill Authoring Conventions) to point at the L1 gate.

## 2. L2 — Skill-doc lint (freeze the audit findings)

- [ ] Add `scripts/lint-skills.sh` (or `.ts`) with one discrete, file:line-reporting rule per check:
  - [ ] Frontmatter present (`name`, `description`) on every SKILL.md.
  - [ ] `## Input` table present where a skill documents arguments.
  - [ ] Every `<!-- include: <path> -->` directive resolves.
  - [ ] Every `plugins/_shared/*.md` citation path resolves.
  - [ ] Every relative markdown link in `plugins/**` and root `README.md` resolves.
  - [ ] README flag-matrix rows agree with the corresponding SKILL.md `## Input` table.
  - [ ] No `develop` branch reference outside designated migration docs (seed allowlist: `flowkit/MIGRATION-v4.md`, openspec archive). **Include `.github/workflows/**`** — `deploy-site.yml` currently trips this.
  - [ ] Every `.claude/settings.json` allowlist script path points at an existing script.
  - [ ] Heuristic: shared specs are cited, not paraphrased inline (flag inlined copies of `pr-body.md` / `base-resolution.md` shape).
- [ ] Wire L2 into `skills-ci.yml` as a required per-PR job.
- [ ] Fix the findings the new linter surfaces on first run (at minimum: `deploy-site.yml` develop triggers; any residual drift).
- [ ] Document each rule and how to add a new one in `evals/README.md`.

## 3. L3 — Behavioral eval harness (highest-blast-radius skill first)

Substrate: **Agent SDK (Python)** — `query()` + `PreToolUse`/`PostToolUse` hooks for tool-call capture.

- [ ] **Depends on the `swarm-epic-arg-mode` change** (separate OpenSpec change): the EPIC_MODE single-epic-arg eval below asserts the behavior that change introduces. Land `swarm-epic-arg-mode` first, then this eval.
- [ ] Add `evals/graders/` (Python): shared programmatic assertion helpers + a calibrated LLM-as-judge wrapper pinned to `claude-sonnet-4-6`, `--max-budget-usd ~0.50` per run (rubric loader, pass/fail parser).
- [ ] Calibrate the judge: assemble 20–50 cases seeded from real failures + audit findings, label by hand, verify `claude-sonnet-4-6` agrees before use.
- [ ] Build fixtures under `evals/fixtures/`: `single-epic-arg`, `epic-8-children-one-blockedby`, `epic-labeled-no-subissues`, `pin-already-set-foreign-feature`, `closes-multiref-one-line`.
- [ ] Author `swarm` evals (one decision each) under `evals/l3/swarm/`:
  - [ ] EPIC_MODE resolution for a single epic arg → asserts `EPIC_MODE=on` + feature-branch cut (encodes the resolved decision).
  - [ ] prBase pin is unset on every exit path (normal, one-shot epic, loop early-exit).
  - [ ] DAG topo-order places a blocked-by child after its parent.
  - [ ] PR body conforms to `pr-body.md` (one `Closes` per line; no bullets in Summary) — judge-graded.
- [ ] Add `evals/l3/catalog/` for the multi-ref `Closes` and consolidation/`--split` decisions.
- [ ] Add `.github/workflows/evals-nightly.yml` running the L3 curated set (scheduled + `workflow_dispatch`), with `--max-turns` / `--max-budget-usd ~0.50` guardrails and **exact** pinned model IDs (`claude-sonnet-4-6`).

## 4. L4 — End-to-end smoke (nightly)

Target: **dedicated test-org GitHub repo**, reset between runs; CI token scoped to that repo only.

- [ ] Stand up the dedicated test-org repo and a reset/seed step (clear issues, branches, labels to a known baseline before each run).
- [ ] Author one full-flow smoke: catalog → swarm → merge-stack on a tiny fixture against the test-org repo; assert issues closed, branches deleted, pin clean, epic closed (exercises the real `gh` issue/PR/sub-issue/dependency APIs).
- [ ] Add it to `evals-nightly.yml` (scheduled + `workflow_dispatch`, never per-PR).

## 5. Convention + docs

- [ ] Author `plugins/_shared/eval-authoring.md`: when a skill needs L1/L2/L3 coverage, fixture/grader conventions, determinism rules (pin exact model IDs, low temperature), cost guardrails.
- [ ] Cross-link it from `CLAUDE.md` Skill Authoring Conventions alongside `script-authoring.md` and `pr-body.md`.
- [ ] `evals/README.md`: how to run each layer locally and in CI.
- [ ] Spec deltas: add the eval-authoring convention and the per-skill eval requirement to the relevant baseline specs at implementation time.
