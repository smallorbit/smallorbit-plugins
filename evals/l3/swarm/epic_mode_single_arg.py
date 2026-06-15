#!/usr/bin/env python3
"""
L3 eval: EPIC_MODE resolution for a single epic argument.

Asserts two paths from the swarm SKILL.md "Epic Mode Resolution" rules:
  1. Single epic arg that expands to >=2 wired children  → EPIC_MODE=on, cut branch.
  2. Single standalone (non-epic) issue arg              → EPIC_MODE=off, no branch.
  3. Single epic arg with no wired children (label only) → EPIC_MODE=off.

Decision encoded by swarm-epic-arg-mode (archived #1070). This eval catches
regressions when SKILL.md changes alter the single-epic-arg probe logic.

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/swarm/epic_mode_single_arg.py
"""
import json
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import decision_probe, EvalResult, run_assertions

_SKILL_MD = os.path.join(REPO_ROOT, "plugins/swarmkit/skills/swarm/SKILL.md")
_FX_DIR = os.path.join(REPO_ROOT, "evals/fixtures")

def _load_skill_section(heading: str, max_lines: int = 80) -> str:
    with open(_SKILL_MD) as f:
        lines = f.readlines()
    in_section = False
    result = []
    for line in lines:
        if line.strip().startswith(f"## {heading}"):
            in_section = True
        elif in_section and line.startswith("## ") and not line.strip().startswith(f"## {heading}"):
            break
        if in_section:
            result.append(line)
            if len(result) >= max_lines:
                break
    return "".join(result)


SYSTEM = (
    "You are executing the swarmkit:swarm skill. Below is the Epic Mode Resolution "
    "section from the skill documentation. Follow it exactly.\n\n"
    + _load_skill_section("Epic Mode Resolution")
)

SCHEMA = '{"is_epic": bool, "epic_mode": "on"|"off", "should_cut_branch": bool, "reason": str}'


def _probe(arg: int, fixture_file: str) -> dict:
    with open(os.path.join(_FX_DIR, fixture_file)) as f:
        gather_output = json.load(f)
    gather_output.pop("_comment", None)
    return decision_probe(
        system=SYSTEM,
        prompt=(
            f"The swarm skill was invoked with argument: {arg}\n\n"
            f"gather_issues.sh {arg} returned:\n{json.dumps(gather_output, indent=2)}\n\n"
            "Based on the Epic Mode Resolution rules:\n"
            "1. Is this argument an epic that expands to >=2 wired children?\n"
            "2. What should EPIC_MODE be set to?\n"
            "3. Should a feature branch be cut?\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )


def test_epic_arg() -> tuple[bool, str]:
    result = _probe(42, "single-epic-arg.json")
    assertions = [
        EvalResult(result.get("is_epic") is True,
                   f"is_epic=true: got {result.get('is_epic')!r}"),
        EvalResult(result.get("epic_mode") == "on",
                   f'epic_mode="on": got {result.get("epic_mode")!r}'),
        EvalResult(result.get("should_cut_branch") is True,
                   f"should_cut_branch=true: got {result.get('should_cut_branch')!r}"),
    ]
    return run_assertions(assertions)


def test_standalone_arg() -> tuple[bool, str]:
    standalone_fixture = {
        "work_items": [{"number": 12, "title": "fix login redirect", "source_epic": None, "blockedBy": []}],
        "epics_expanded": [],
        "is_epic": False,
        "epics_unwired": [],
    }
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "The swarm skill was invoked with argument: 12\n\n"
            f"gather_issues.sh 12 returned:\n{json.dumps(standalone_fixture, indent=2)}\n\n"
            "Based on the Epic Mode Resolution rules:\n"
            "1. Is this argument an epic that expands to >=2 wired children?\n"
            "2. What should EPIC_MODE be set to?\n"
            "3. Should a feature branch be cut?\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )
    assertions = [
        EvalResult(result.get("is_epic") is False,
                   f"is_epic=false: got {result.get('is_epic')!r}"),
        EvalResult(result.get("epic_mode") == "off",
                   f'epic_mode="off": got {result.get("epic_mode")!r}'),
        EvalResult(result.get("should_cut_branch") is False,
                   f"should_cut_branch=false: got {result.get('should_cut_branch')!r}"),
    ]
    return run_assertions(assertions)


def test_epic_labeled_no_subissues() -> tuple[bool, str]:
    result = _probe(7, "epic-labeled-no-subissues.json")
    assertions = [
        EvalResult(result.get("is_epic") is False,
                   f"is_epic=false (no wired children): got {result.get('is_epic')!r}"),
        EvalResult(result.get("epic_mode") == "off",
                   f'epic_mode="off" (epics_unwired): got {result.get("epic_mode")!r}'),
    ]
    return run_assertions(assertions)


def main() -> None:
    cases = [
        ("epic arg #42 (2 wired children) → EPIC_MODE=on", test_epic_arg),
        ("standalone issue #12 → EPIC_MODE=off",           test_standalone_arg),
        ("epic label, no sub-issues #7 → EPIC_MODE=off",   test_epic_labeled_no_subissues),
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
