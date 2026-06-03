## ADDED Requirements

### Requirement: Script Test Gate (L1)
Every script-backed skill SHALL ship a sibling `scripts/test.sh`, and a CI job SHALL run all such tests on pull requests touching `plugins/**`, failing the check on any non-zero exit.

#### Scenario: All skill tests discovered and run
- **WHEN** the L1 runner executes
- **THEN** it discovers every `plugins/*/skills/*/scripts/test.sh` (via `find ... | while read`, never `for N in $(...)`) and runs each one

#### Scenario: Any failing test fails the gate
- **WHEN** any discovered `test.sh` exits non-zero
- **THEN** the CI job fails and reports which skill's test failed

#### Scenario: Script-backed skill missing a test is rejected
- **WHEN** a skill ships a `scripts/` directory with no sibling `test.sh`
- **THEN** the convention is violated and the omission is surfaced (lint or CI)

### Requirement: Skill-Doc Lint (L2)
A no-LLM linter SHALL assert structural invariants across `plugins/**` and root docs on every pull request, with each rule reporting a `file:line` location, and SHALL run as a required check.

#### Scenario: Unresolved include or citation fails the lint
- **WHEN** a SKILL.md contains an `<!-- include: <path> -->` directive or a `plugins/_shared/*.md` citation whose path does not exist
- **THEN** the linter reports the offending `file:line` and the check fails

#### Scenario: Stale develop reference fails the lint
- **WHEN** a `develop` branch reference appears outside the designated migration-doc allowlist (including under `.github/workflows/**`)
- **THEN** the linter flags it

#### Scenario: Allowlist entry pointing at a removed script fails the lint
- **WHEN** a `.claude/settings.json` allowlist entry references a script path that does not exist in the tree
- **THEN** the linter flags it as a dead permission surface

#### Scenario: README flag-matrix drift fails the lint
- **WHEN** a plugin README flag-matrix row disagrees with the corresponding SKILL.md `## Input` table
- **THEN** the linter flags the divergence

### Requirement: Behavioral Eval Harness (L3)
High-blast-radius skill decisions SHALL be covered by behavioral evals that run the skill headlessly against a seeded fixture, capture the tool-call trajectory and resulting state, and grade with programmatic assertions (preferred) plus a calibrated LLM-as-judge for fuzzy criteria. Behavioral evals SHALL NOT block per-PR merges.

#### Scenario: One decision per eval
- **WHEN** a behavioral eval is authored
- **THEN** it targets a single runbook decision (e.g. EPIC_MODE resolution for a single epic arg) and asserts structured behavior, not the model's prose

#### Scenario: Deterministic invocation
- **WHEN** a behavioral eval runs a skill headlessly
- **THEN** it pins an exact model ID (not a floating alias), uses low temperature and JSON output, and applies `--max-turns` / `--max-budget-usd` guardrails

#### Scenario: Judge calibrated before use
- **WHEN** an LLM-as-judge grader is introduced
- **THEN** it is validated against human labels on a seeded sample before its verdicts are trusted

#### Scenario: Behavioral evals run off the blocking path
- **WHEN** behavioral evals execute in CI
- **THEN** they run on a scheduled or label-gated job, never as a required per-PR check

### Requirement: Eval Authoring Convention
The repository SHALL document, in a shared convention, when and how a skill adds coverage at each eval layer, and the convention SHALL be cross-linked from the skill-authoring guidance.

#### Scenario: New skill follows the convention
- **WHEN** a new skill or script is authored
- **THEN** `plugins/_shared/eval-authoring.md` specifies the required layer coverage, fixture/grader conventions, and determinism/cost rules, and is referenced from `CLAUDE.md`
