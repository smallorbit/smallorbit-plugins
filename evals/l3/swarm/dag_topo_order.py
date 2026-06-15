#!/usr/bin/env python3
"""
L3 eval: DAG topo-order — blocked issue processed after its parent.

Asserts that when gather_issues.sh returns a work-item set with blockedBy
dependencies, the model orders execution so blocked children are assigned
to agents after their parents (never in parallel with or before them).

Uses the epic-8-children-one-blockedby fixture (#17 blocked by #12, #14, #15).

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/swarm/dag_topo_order.py
"""
import json
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import decision_probe, EvalResult, assert_before, run_assertions

_SKILL_MD = os.path.join(REPO_ROOT, "plugins/swarmkit/skills/swarm/SKILL.md")
_FX_DIR = os.path.join(REPO_ROOT, "evals/fixtures")


def _load_ordering_section(max_chars: int = 3000) -> str:
    with open(_SKILL_MD) as f:
        content = f.read()
    for keyword in ("DAG", "topo", "blocked", "blockedBy", "dependency order"):
        idx = content.find(keyword)
        if idx != -1:
            start = max(0, content.rfind("##", 0, idx))
            return content[start: start + max_chars]
    return content[:max_chars]


SYSTEM = (
    "You are executing the swarmkit:swarm skill. Below is an excerpt from the skill "
    "documentation describing how to handle issue dependencies (blockedBy).\n\n"
    + _load_ordering_section()
)

SCHEMA = '{"processing_order": [int], "reason": str}'


def test_blocked_after_parent() -> tuple[bool, str]:
    with open(os.path.join(_FX_DIR, "epic-8-children-one-blockedby.json")) as f:
        fixture = json.load(f)
    fixture.pop("_comment", None)

    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "gather_issues.sh returned the following work items:\n"
            f"{json.dumps(fixture['work_items'], indent=2)}\n\n"
            "Issues #12, #14, and #15 must complete before #17 can start (blockedBy).\n"
            "The other issues (#10, #11, #13, #16) have no blockedBy dependencies.\n\n"
            "In what order should the swarm agents be dispatched? "
            "List ALL issue numbers in the order agents would be assigned (parallel "
            "agents can share the same logical 'batch' position — put them in "
            "ascending numeric order within a batch).\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )

    order = result.get("processing_order", [])
    assertions = [
        EvalResult(
            17 in order,
            f"#17 is in the processing order: {order}"
        ),
        EvalResult(
            12 in order and order.index(12) < order.index(17),
            f"#12 before #17: {order}"
        ),
        EvalResult(
            14 in order and order.index(14) < order.index(17),
            f"#14 before #17: {order}"
        ),
        EvalResult(
            15 in order and order.index(15) < order.index(17),
            f"#15 before #17: {order}"
        ),
    ]
    return run_assertions(assertions)


def test_simple_chain() -> tuple[bool, str]:
    """A→B chain: #101 must precede #102."""
    simple_items = [
        {"number": 101, "title": "step one", "source_epic": 42, "blockedBy": []},
        {"number": 102, "title": "step two", "source_epic": 42, "blockedBy": [101]},
    ]
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "gather_issues.sh returned these work items:\n"
            f"{json.dumps(simple_items, indent=2)}\n\n"
            "Issue #102 is blocked by #101 and cannot start until #101 is complete.\n\n"
            "In what order should agents be dispatched?\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )
    order = result.get("processing_order", [])
    passed, summary = run_assertions([
        EvalResult(
            101 in order and 102 in order and order.index(101) < order.index(102),
            f"#101 before #102: {order}"
        )
    ])
    return passed, summary


def main() -> None:
    cases = [
        ("8-item epic: #17 blocked by #12, #14, #15 → those must precede #17", test_blocked_after_parent),
        ("simple 2-item chain: #101 → #102",                                    test_simple_chain),
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
