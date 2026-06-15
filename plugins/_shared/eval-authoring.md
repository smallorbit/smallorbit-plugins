# Eval Authoring Convention

Every skill that carries blast-radius decisions needs regression coverage. This
document defines when to add evals, which layer to use, and how to structure them.

Cross-referenced from `CLAUDE.md` Skill Authoring Conventions.
Full strategy and per-layer details: [`evals/README.md`](../../evals/README.md).

## When a skill needs evals

| Condition | Minimum coverage |
|-----------|-----------------|
| Skill ships shell scripts | L1 `test.sh` (mandatory — see `script-authoring.md`) |
| Skill mutates git state, PRs, or labels | L3 behavioral eval for each high-blast decision |
| Audit finding is introduced as a rule | L2 lint rule (the fix + the ratchet land together) |
| Skill drives a sub-skill that already has L3 coverage | Not required — defer to the sub-skill's evals |

## Layer quick-reference

| Layer | Where | Cost | CI gate |
|-------|-------|------|---------|
| L1 — script unit tests | `plugins/<p>/skills/<s>/scripts/test.sh` | free | per-PR (required check) |
| L2 — skill-doc lint | `scripts/lint-skills.py` rules | free | per-PR (required check) |
| L3 — behavioral evals | `evals/l3/<skill>/<decision>.py` | LLM tokens | nightly |
| L4 — E2E smoke | `evals/l4/` | LLM + real GitHub API | nightly |

## L1 — test.sh convention

Covered by `script-authoring.md`. Short version: every `scripts/*.sh` must have a
sibling `test.sh` that exercises argument validation and JSON contract. The repo-root
runner discovers and runs them; a missing or failing `test.sh` blocks merge.

## L3 — behavioral eval structure

Use the **decision-probe** pattern (see `evals/graders/run.py`):

1. Load the relevant SKILL.md section as the system prompt.
2. Describe a specific fixture scenario as the user turn.
3. Ask the model to make ONE decision as structured JSON.
4. Assert programmatically.

```python
from evals.graders import decision_probe, EvalResult, run_assertions

result = decision_probe(
    system=<skill_section>,        # excerpt from SKILL.md
    prompt=<scenario_description>, # fixture + question
    response_schema_desc=<schema>, # JSON schema string
)
assertions = [EvalResult(result["key"] == expected, "label")]
passed, summary = run_assertions(assertions)
```

### One decision per eval

Each eval file targets ONE branching decision in the skill:
- `epic_mode_single_arg.py` — does a single epic arg resolve EPIC_MODE=on?
- `prbase_pin_lifecycle.py` — is prBase unset on every exit path?
- `dag_topo_order.py` — does a blocked issue come after its parent?

"Does the skill work?" is not a valid eval — it is unfalsifiable and flaky.

### Determinism rules

- Pin **exact** model IDs: `"claude-sonnet-4-6"`, not the floating `"sonnet"` alias.
- Use low/default temperature (the API default is sufficient).
- Seed fixture data; never rely on wall-clock or random state.
- Set `budget_usd` to ≤$0.10 per eval (enforced by `decision_probe()`).

### Judge-graded evals

Use `evals/graders/judge.py` for fuzzy assertions where programmatic checks are
insufficient (PR body conformance, plan correctness). Always:

- Include a tight rubric with explicit pass/fail criteria — no open-ended questions.
- **Calibrate before relying on CI.** Run `evals/calibration/check_agreement.py`
  against labeled samples and verify ≥90% agreement. See `evals/calibration/README.md`.
- Default to FAIL in the judge system prompt — only pass when ALL criteria are met.

### File naming

```
evals/
  fixtures/<scenario>.json   # mock gh API responses or fixture text
  l3/<skill>/<decision>.py   # one decision per file, snake_case
```

## L4 — end-to-end smoke

Reserved for full-flow runs (catalog → swarm → merge-stack) against a dedicated
test-org GitHub repo. L4 requires the `SMALLORBIT_TEST_ORG_TOKEN` secret and a
reset/seed step. See `evals/README.md § L4` for the setup protocol. Do not use
real production repos — the smoke resets issue and branch state between runs.

## Adding a new L3 eval

1. Identify the decision: one branching point in a high-blast skill.
2. Create a fixture JSON in `evals/fixtures/` if the eval needs mock gh data.
3. Write `evals/l3/<skill>/<decision>.py` using the decision-probe pattern.
4. Add the script to the corresponding job in `.github/workflows/evals-nightly.yml`.
5. If judge-graded: add samples to `evals/calibration/samples.jsonl` and run
   `check_agreement.py` before merging.
6. Update `evals/README.md` rule catalog with the new eval.
