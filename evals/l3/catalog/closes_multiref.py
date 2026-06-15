#!/usr/bin/env python3
"""
L3 eval: Closes multi-ref formatting — one token per line.

Asserts that the model knows GitHub's closing-keyword grammar: putting
multiple issue refs on one line ('Closes #A #B') only closes #A. Each
issue must get its own 'Closes #N' line.

This is a key pattern from pr-body.md and the 2026-06-01 audit.

Run:
  ANTHROPIC_API_KEY=... python3 evals/l3/catalog/closes_multiref.py
"""
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders import decision_probe, EvalResult, run_assertions

_PR_BODY_SPEC = os.path.join(REPO_ROOT, "plugins/_shared/pr-body.md")

with open(_PR_BODY_SPEC) as f:
    _SPEC = f.read()

SYSTEM = (
    "You are writing PR bodies for GitHub. Follow the canonical pr-body.md spec exactly.\n\n"
    + _SPEC
)

SCHEMA = '{"footer": str, "reason": str}'


def test_three_issues_separate_lines() -> tuple[bool, str]:
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "A PR fully resolves three issues: #88, #89, and #90.\n\n"
            "Write the correct issue-reference footer for this PR.\n\n"
            f"Respond with JSON matching: {SCHEMA}\n"
            "The 'footer' field should contain only the issue-reference lines."
        ),
        response_schema_desc=SCHEMA,
    )
    footer = result.get("footer", "")
    assertions = [
        EvalResult(
            "Closes #88" in footer and "Closes #89" in footer and "Closes #90" in footer,
            f"all three Closes tokens present: {footer!r}"
        ),
        EvalResult(
            "Closes #88 #89" not in footer and "Closes #88 #90" not in footer,
            f"no multi-ref on one line: {footer!r}"
        ),
        EvalResult(
            footer.count("Closes #") == 3,
            f"exactly 3 Closes lines: got {footer.count('Closes #')}: {footer!r}"
        ),
    ]
    return run_assertions(assertions)


def test_partial_progress_uses_refs() -> tuple[bool, str]:
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "A PR fully resolves child issue #55. "
            "It partially advances parent epic #50 but does not close it.\n\n"
            "Write the correct issue-reference footer.\n\n"
            f"Respond with JSON matching: {SCHEMA}"
        ),
        response_schema_desc=SCHEMA,
    )
    footer = result.get("footer", "")
    assertions = [
        EvalResult(
            "Closes #55" in footer,
            f"Closes for fully-resolved child: {footer!r}"
        ),
        EvalResult(
            "Refs #50" in footer,
            f"Refs for parent epic: {footer!r}"
        ),
        EvalResult(
            "Closes #50" not in footer,
            f"epic NOT closed: {footer!r}"
        ),
    ]
    return run_assertions(assertions)


def test_no_fixes_resolves() -> tuple[bool, str]:
    result = decision_probe(
        system=SYSTEM,
        prompt=(
            "A PR fully resolves issue #77.\n\n"
            "What closing keyword should be used — Closes, Fixes, or Resolves?\n\n"
            "Respond with JSON: {\"keyword\": str, \"footer\": str, \"reason\": str}"
        ),
        response_schema_desc='{"keyword": str, "footer": str, "reason": str}',
    )
    keyword = result.get("keyword", "")
    assertions = [
        EvalResult(
            keyword == "Closes",
            f"canonical keyword is 'Closes', not '{keyword}'"
        ),
    ]
    return run_assertions(assertions)


def main() -> None:
    cases = [
        ("three issues → separate Closes lines",    test_three_issues_separate_lines),
        ("partial progress → Closes + Refs",         test_partial_progress_uses_refs),
        ("keyword choice → Closes not Fixes",        test_no_fixes_resolves),
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
