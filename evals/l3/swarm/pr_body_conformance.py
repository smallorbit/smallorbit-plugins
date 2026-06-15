#!/usr/bin/env python3
"""
L3 eval: PR body conformance to plugins/_shared/pr-body.md (judge-graded).

Uses the LLM-as-judge to verify that PR bodies produced by swarm agents
conform to the canonical three-section + footer spec. Tests both a
conforming body and a known-violation body to validate judge accuracy.

Calibrated against samples in evals/calibration/samples.jsonl. See
evals/calibration/README.md before trusting verdicts in production CI.

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/swarm/pr_body_conformance.py
"""
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import judge, EvalResult, run_assertions

_PR_BODY_SPEC = os.path.join(REPO_ROOT, "plugins/_shared/pr-body.md")
_FX_DIR = os.path.join(REPO_ROOT, "evals/fixtures")


def _load_rubric() -> str:
    with open(_PR_BODY_SPEC) as f:
        spec = f.read()
    return (
        "A PR body PASSES only if ALL of the following hold:\n"
        "1. Starts with ## Summary (1-3 sentences, no bullets, no file paths, no title restatement).\n"
        "2. Has ## Changes with a bulleted list.\n"
        "3. Has ## Test plan with a checklist (- [ ] items).\n"
        "4. Has an issue-reference footer with one token per line (Closes #N or Refs #N) — "
        "   never 'Closes #A #B' on a single line.\n"
        "5. Uses 'Closes' (not 'Fixes' or 'Resolves') for newly authored bodies.\n\n"
        "Spec:\n" + spec
    )


RUBRIC = _load_rubric()

CONFORMING_BODY = """\
## Summary

Standardize the PR body shape across flowkit and swarmkit so reviewers see the
same three sections on every PR and release-time ref aggregation picks up every
`Closes` token.

## Changes

- `plugins/_shared/pr-body.md` — add canonical spec.
- `plugins/flowkit/skills/open-pr/SKILL.md` — reference canonical shape.
- `plugins/swarmkit/skills/swarm/SKILL.md` — update agent PR template.

## Test plan

- [ ] Open a PR via `/flowkit:open-pr` and confirm all three sections appear.
- [ ] Include `Closes #123` in a commit; confirm it appears in the PR footer.

Closes #521
Closes #522
Refs #526
"""

MULTIREF_ONE_LINE_BODY = open(os.path.join(_FX_DIR, "closes-multiref-one-line.md")).read()

BULLETS_IN_SUMMARY_BODY = """\
## Summary

- Add user profile feature.
- Include avatar upload support.
- Fix redirect on logout.

## Changes

- `handler.py` — add profile endpoint.

## Test plan

- [ ] Profile page loads correctly.

Closes #88
"""

MISSING_TEST_PLAN_BODY = """\
## Summary

Fix null pointer dereference in the config loader when the file is missing.

## Changes

- `config.py:42` — add early return on missing file path.

Closes #55
"""


def _test(name: str, body: str, expect_pass: bool) -> tuple[bool, str]:
    verdict = judge(content=body, rubric=RUBRIC)
    actual_pass = verdict.get("passed", False)
    correct = actual_pass == expect_pass
    assertions = [
        EvalResult(
            correct,
            f"judge={'PASS' if actual_pass else 'FAIL'}, expected={'PASS' if expect_pass else 'FAIL'}: "
            f"{verdict.get('reasoning', '')}"
        )
    ]
    return run_assertions(assertions)


def main() -> None:
    cases = [
        ("conforming body → judge PASS",            CONFORMING_BODY,            True),
        ("Closes #A #B on one line → judge FAIL",   MULTIREF_ONE_LINE_BODY,     False),
        ("bullets in Summary → judge FAIL",          BULLETS_IN_SUMMARY_BODY,    False),
        ("missing ## Test plan → judge FAIL",        MISSING_TEST_PLAN_BODY,     False),
    ]
    all_passed = True
    for name, body, expect_pass in cases:
        print(f"=== {name} ===")
        passed, summary = _test(name, body, expect_pass)
        print(summary)
        if not passed:
            all_passed = False
        print()
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
