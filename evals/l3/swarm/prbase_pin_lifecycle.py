#!/usr/bin/env python3
"""
L3 eval: prBase pin lifecycle — unset on every swarm exit path.

Asserts that the model correctly identifies teardown.sh must be called
(which unsets claude.flowkit.prBase) on all three exit paths:
  1. Normal loop completion (all issues processed).
  2. One-shot epic completion (single epic arg run finished).
  3. Loop early-exit (board is clear, zero issues selected).

The prBase leak was a real regression caught in the 2026-06-01 audit (#1054);
this eval guards against it re-emerging after SKILL.md edits.

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/swarm/prbase_pin_lifecycle.py
"""
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import decision_probe, EvalResult, run_assertions

_SKILL_MD = os.path.join(REPO_ROOT, "plugins/swarmkit/skills/swarm/SKILL.md")


def _load_teardown_section(max_lines: int = 100) -> str:
    with open(_SKILL_MD) as f:
        lines = f.readlines()
    result = []
    in_teardown = False
    for line in lines:
        if "Teardown" in line and line.startswith("#"):
            in_teardown = True
        elif in_teardown and line.startswith("## "):
            break
        if in_teardown:
            result.append(line)
            if len(result) >= max_lines:
                break
    # Also grab the closing prBase unset lines for context
    if not result:
        # Fall back to searching for prBase mentions
        for i, line in enumerate(lines):
            if "prBase" in line and "teardown" in lines[max(0, i-5):i+5]:
                result.extend(lines[max(0, i-3):min(len(lines), i+5)])
    return "".join(result) if result else "(teardown section not found — scan SKILL.md for prBase handling)"


def _load_skill_snippet() -> str:
    with open(_SKILL_MD) as f:
        content = f.read()
    # Extract a focused excerpt covering teardown and loop exit
    start = content.find("## Teardown")
    if start == -1:
        start = content.find("teardown")
    end = start + 3000 if start != -1 else 3000
    return content[max(0, start):end]


SYSTEM = (
    "You are executing the swarmkit:swarm skill. Below is an excerpt from the skill documentation "
    "covering teardown and exit paths. Follow it exactly.\n\n"
    + _load_skill_snippet()
)

SCHEMA = (
    '{"calls_teardown": bool, "prbase_unset": bool, "reason": str}'
)


def _probe(scenario: str) -> dict:
    return decision_probe(
        system=SYSTEM,
        prompt=(
            f"Scenario: {scenario}\n\n"
            "Based on the skill documentation:\n"
            "1. Should teardown.sh be called in this scenario?\n"
            "2. Will claude.flowkit.prBase be unset after this exit path completes?\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )


def test_normal_completion() -> tuple[bool, str]:
    result = _probe(
        "Swarm loop mode ran successfully. All open issues have been processed "
        "and PRs have been opened for each. The loop has no more issues to pick up."
    )
    assertions = [
        EvalResult(result.get("calls_teardown") is True,
                   f"normal completion: calls_teardown=true: got {result.get('calls_teardown')!r}"),
        EvalResult(result.get("prbase_unset") is True,
                   f"normal completion: prbase_unset=true: got {result.get('prbase_unset')!r}"),
    ]
    return run_assertions(assertions)


def test_one_shot_epic_completion() -> tuple[bool, str]:
    result = _probe(
        "Swarm was run in one-shot epic mode with /swarm 42. Issue #42 is an epic "
        "with children #101 and #102. Both children have been processed and PRs opened. "
        "The one-shot run is now complete."
    )
    assertions = [
        EvalResult(result.get("calls_teardown") is True,
                   f"one-shot epic: calls_teardown=true: got {result.get('calls_teardown')!r}"),
        EvalResult(result.get("prbase_unset") is True,
                   f"one-shot epic: prbase_unset=true: got {result.get('prbase_unset')!r}"),
    ]
    return run_assertions(assertions)


def test_empty_board_early_exit() -> tuple[bool, str]:
    result = _probe(
        "Swarm loop mode started. gh issue list returned zero open issues — "
        "the board is clear. Swarm announces 'Board is clear' and exits early "
        "without processing any issues."
    )
    assertions = [
        EvalResult(result.get("prbase_unset") is True,
                   f"empty board: prbase_unset=true: got {result.get('prbase_unset')!r}"),
    ]
    return run_assertions(assertions)


def main() -> None:
    cases = [
        ("normal loop completion → teardown + prBase unset",     test_normal_completion),
        ("one-shot epic completion → teardown + prBase unset",   test_one_shot_epic_completion),
        ("empty board early-exit → prBase unset",                test_empty_board_early_exit),
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
