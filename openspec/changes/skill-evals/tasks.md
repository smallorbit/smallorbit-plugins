# tasks

Implementation decomposition for the skill-evals strategy. Phased so the cheap, deterministic, high-ROI layers (L1, L2) land and gate first; LLM-in-loop layers (L3, L4) follow. Each phase is independently shippable.

## 1. L1 — Script unit tests (gate the tests that already exist)

- [x] Reuse the existing `scripts/test-all-skill-scripts.sh` runner (discovers every `plugins/*/skills/*/scripts/test.sh`, runs each, fails on any non-zero exit, summarizes pass/fail per skill) instead of adding a duplicate `run-skill-tests.sh`.
- [x] Add `.github/workflows/skills-ci.yml` with an L1 job that runs `scripts/test-all-skill-scripts.sh` on PRs touching `plugins/**`. (Mark it a required check in branch protection.)
- [x] Backfill `test.sh` for script-backed skills that lack one — none needed; all 6 script-backed skills already ship one.
- [x] Update `plugins/_shared/script-authoring.md`: `test.sh` is mandatory for any script-backed skill; reference the runner + CI gate.
- [x] Update `CLAUDE.md` (Skill Authoring Conventions) to point at the L1 gate.

## 2. L2 — Skill-doc lint (freeze the audit findings)

- [x] Add `scripts/lint-skills.py` (Python stdlib — table parsing is impractical in pure bash; CI has `python3`) with one discrete, file:line-reporting rule per check. Each rule carries an ERROR/WARN severity; only ERROR fails the gate (keeps a noisy rule from blocking merges until it is calibrated):
  - [x] Frontmatter present (`name`, `description`) on every SKILL.md. (ERROR)
  - [x] `## Input`/Arguments section present where a skill documents arguments. (WARN — args are documented under varied headings)
  - [x] Every `<!-- include: <path> -->` directive resolves. (ERROR)
  - [x] Every `plugins/_shared/*.md` citation path resolves. (ERROR)
  - [x] Every relative markdown link in `plugins/**` and root `README.md` resolves. (ERROR — fenced code blocks skipped)
  - [x] README flag-matrix agreement with SKILL.md documented flags. (WARN — coarse heuristic; README tables are skill-catalogs, not strict per-flag matrices)
  - [x] No `develop` branch reference outside the migration/legacy allowlist (incl. `.github/workflows/**`). (ERROR — branch-ref gate + negative-context + file allowlist + `lint-allow-develop` marker)
  - [x] Every `.claude/settings.json` allowlist script path points at an existing script. (ERROR)
  - [x] Heuristic: shared specs are cited, not paraphrased inline (flag inlined `pr-body.md` shape). (WARN)
- [x] Wire L2 into `skills-ci.yml` as a per-PR job. (Mark it a required check in branch protection.)
- [x] Fix the findings the new linter surfaced on first run: `deploy-site.yml` develop trigger; `polish/SKILL.md:30` stale develop/repo-default step (closes #1068); `sweep/SKILL.md:171` stale develop auto-detect.
- [x] Document each rule and how to add a new one in `evals/README.md`.

## 3. L3 — Behavioral eval harness (highest-blast-radius skill first)

Substrate: **decision-probe pattern** — Anthropic Python SDK (`pip install anthropic`), one decision per eval, structured JSON output, `evals/graders/` helpers.

- [x] ~~Depends on `swarm-epic-arg-mode`~~ — archived (#1070), dependency cleared.
- [x] Add `evals/graders/` (Python): `assertions.py` (EvalResult helpers), `run.py` (decision_probe via Anthropic SDK), `judge.py` (LLM-as-judge pinned to `claude-sonnet-4-6`, $0.10 budget cap).
- [x] Calibrate the judge: 25 PR-body samples in `evals/calibration/samples.jsonl` (seeded from audit findings); `check_agreement.py` runner; `evals/calibration/README.md` protocol. **Human labels required before CI use — see calibration/README.md.**
- [x] Build fixtures under `evals/fixtures/`: `single-epic-arg.json`, `epic-8-children-one-blockedby.json`, `epic-labeled-no-subissues.json`, `pin-already-set-foreign-feature.json`, `closes-multiref-one-line.md`.
- [x] Author `swarm` evals under `evals/l3/swarm/`:
  - [x] `epic_mode_single_arg.py` — EPIC_MODE resolution for single epic / standalone / unwired-epic.
  - [x] `prbase_pin_lifecycle.py` — prBase unset on normal completion, one-shot epic, empty-board early-exit.
  - [x] `dag_topo_order.py` — blocked issue dispatched after its parent (8-item fixture + simple chain).
  - [x] `pr_body_conformance.py` — judge-graded: conforming body PASS, three violation bodies FAIL.
- [x] Add `evals/l3/catalog/`: `closes_multiref.py` (one Closes per line, Refs for epics, Closes keyword) + `split_decision.py` (shared-scope consolidation, interdep split, --split flag).
- [x] Add `.github/workflows/evals-nightly.yml`: `l3-swarm` + `l3-catalog` jobs (scheduled 04:00 UTC + `workflow_dispatch`), `pip install anthropic==0.40.0`, pinned model IDs. L4 job stubbed/commented.

## 4. L4 — End-to-end smoke (nightly)

Target: **dedicated test-org GitHub repo**, reset between runs; CI token scoped to that repo only.

- [ ] Stand up the dedicated test-org repo and a reset/seed step (clear issues, branches, labels to a known baseline before each run). **Requires user action: create test GitHub org and add `SMALLORBIT_TEST_ORG_TOKEN` secret.**
- [ ] Author `evals/l4/smoke.py`: full-flow smoke (catalog → swarm → merge-stack); assert issues closed, branches deleted, pin clean, epic closed.
- [ ] Uncomment `l4-smoke` job in `evals-nightly.yml` and add `SMALLORBIT_TEST_ORG_REPO` variable.

## 5. Convention + docs

- [x] Author `plugins/_shared/eval-authoring.md`: when a skill needs L1/L2/L3 coverage, fixture/grader conventions, determinism rules (pin exact model IDs), cost guardrails, judge calibration protocol.
- [x] Cross-link `eval-authoring.md` from `CLAUDE.md` Skill Authoring Conventions alongside `script-authoring.md` and `pr-body.md`.
- [x] `evals/README.md`: L3 run instructions, eval catalog, judge calibration, L4 setup protocol.
- [x] Spec deltas: `openspec/specs/` updated at archive time (see archive step).
