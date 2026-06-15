#!/usr/bin/env python3
"""
L3 eval: catalog consolidation vs --split decision.

Asserts the model correctly applies the phase-mate consolidation heuristic
from speckit:catalog SKILL.md:
  - Rows with shared scope + no inter-dep → consolidate (default).
  - Rows with different scope or inter-deps → stay split.
  - --split flag → always one issue per row.

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/catalog/split_decision.py
"""
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import decision_probe, EvalResult, run_assertions

_CATALOG_SKILL = os.path.join(
    REPO_ROOT, "plugins/speckit/skills/catalog/SKILL.md"
)


def _load_consolidation_section() -> str:
    with open(_CATALOG_SKILL) as f:
        content = f.read()
    start = content.find("### 1.5")
    end = content.find("### 1.6")
    if start == -1 or end == -1:
        return content[:3000]
    return content[start:end]


SYSTEM = (
    "You are executing the speckit:catalog skill. Below is the consolidation section "
    "of the skill documentation. Apply it exactly.\n\n"
    + _load_consolidation_section()
)

CONSOLIDATE_SCHEMA = '{"action": "consolidate"|"split", "issue_count": int, "reason": str}'
SPLIT_FLAG_SCHEMA  = '{"action": "consolidate"|"split", "issue_count": int, "reason": str}'


def test_shared_scope_no_interdep_consolidates() -> tuple[bool, str]:
    """Three same-phase rows with shared scope and no inter-deps → 1 issue."""
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "Phase 2 has these rows:\n"
            "  - Port shadcn primitive: Button\n"
            "  - Port shadcn primitive: Input\n"
            "  - Port shadcn primitive: Select\n\n"
            "All three describe the same mechanical work (port a shadcn primitive), "
            "share identical acceptance criteria, and none depends on the others.\n\n"
            "Should these rows consolidate into one issue, or stay as three separate issues?\n\n"
            f"Respond with JSON matching: {CONSOLIDATE_SCHEMA}"
        ),
        response_schema_desc=CONSOLIDATE_SCHEMA,
    )
    assertions = [
        EvalResult(
            result.get("action") == "consolidate",
            f"shared scope + no interdep → consolidate: got {result.get('action')!r}: {result.get('reason', '')}"
        ),
        EvalResult(
            result.get("issue_count") == 1,
            f"1 issue after consolidation: got {result.get('issue_count')!r}"
        ),
    ]
    return run_assertions(assertions)


def test_interdependency_stays_split() -> tuple[bool, str]:
    """Row B depends on row A in the same phase → must not consolidate."""
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "Phase 3 has these rows:\n"
            "  - Implement data model (row A)\n"
            "  - Add API layer (row B) — explicitly depends on row A being merged first\n\n"
            "Row B has row A as a strict ordering dependency.\n\n"
            "Should these rows consolidate into one issue, or stay as two separate issues?\n\n"
            f"Respond with JSON matching: {CONSOLIDATE_SCHEMA}"
        ),
        response_schema_desc=CONSOLIDATE_SCHEMA,
    )
    assertions = [
        EvalResult(
            result.get("action") == "split",
            f"interdependency → split: got {result.get('action')!r}: {result.get('reason', '')}"
        ),
        EvalResult(
            result.get("issue_count") == 2,
            f"2 issues (split): got {result.get('issue_count')!r}"
        ),
    ]
    return run_assertions(assertions)


def test_split_flag_bypasses_consolidation() -> tuple[bool, str]:
    """--split flag present → one issue per row regardless of shared scope."""
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "The catalog skill was invoked with --split.\n\n"
            "Phase 2 has these rows:\n"
            "  - Port shadcn primitive: Button\n"
            "  - Port shadcn primitive: Input\n"
            "  - Port shadcn primitive: Select\n\n"
            "All three have shared scope and no inter-deps — but --split was passed.\n\n"
            "How many issues should be filed?\n\n"
            f"Respond with JSON matching: {SPLIT_FLAG_SCHEMA}"
        ),
        response_schema_desc=SPLIT_FLAG_SCHEMA,
    )
    assertions = [
        EvalResult(
            result.get("action") == "split",
            f"--split flag → one per row: got {result.get('action')!r}"
        ),
        EvalResult(
            result.get("issue_count") == 3,
            f"3 issues with --split: got {result.get('issue_count')!r}"
        ),
    ]
    return run_assertions(assertions)


def main() -> None:
    cases = [
        ("shared scope, no interdep → consolidate to 1 issue",  test_shared_scope_no_interdep_consolidates),
        ("row B depends on row A → stay split (2 issues)",       test_interdependency_stays_split),
        ("--split flag → one per row regardless",               test_split_flag_bypasses_consolidation),
    ]
    all_passed = True
    for name, fn in cases:
        print(f"=== {name} ===")
        passed, summary = fn()
        print(summary)
        if not passed:
            all_passed = False
        print()
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
