#!/usr/bin/env python3
"""
Calibration agreement check.

Runs the LLM judge on every labeled sample in samples.jsonl and
reports the agreement rate with human labels.

Usage:
  ANTHROPIC_API_KEY=... python3 evals/calibration/check_agreement.py

Requires human_label to be filled in for all samples — see README.md.
"""
import json
import sys
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
sys.path.insert(0, REPO_ROOT)

from evals.graders.judge import judge

_SAMPLES = os.path.join(os.path.dirname(__file__), "samples.jsonl")
_PR_BODY_SPEC = os.path.join(REPO_ROOT, "plugins/_shared/pr-body.md")

with open(_PR_BODY_SPEC) as f:
    _SPEC = f.read()

RUBRIC = (
    "A PR body PASSES only if ALL of the following hold:\n"
    "1. Starts with ## Summary (1-3 sentences, no bullets, no file paths, no title restatement).\n"
    "2. Has ## Changes with a bulleted list.\n"
    "3. Has ## Test plan with a checklist (- [ ] items).\n"
    "4. Has an issue-reference footer with one token per line.\n"
    "5. Uses 'Closes' not 'Fixes' or 'Resolves'.\n\n"
    "Spec:\n" + _SPEC
)


def main() -> None:
    with open(_SAMPLES) as f:
        samples = [json.loads(line) for line in f if line.strip()]

    unlabeled = [s for s in samples if s.get("human_label") is None]
    if unlabeled:
        print(f"WARNING: {len(unlabeled)} samples have no human_label — skipping them.")
        print("Fill in human_label in samples.jsonl before running calibration.\n")
        samples = [s for s in samples if s.get("human_label") is not None]

    if not samples:
        print("No labeled samples found. See evals/calibration/README.md.")
        sys.exit(1)

    agree = 0
    disagree = 0
    errors = 0

    for sample in samples:
        try:
            verdict = judge(content=sample["content"], rubric=RUBRIC)
            judge_pass = verdict.get("passed", False)
            human_pass = bool(sample["human_label"])
            if judge_pass == human_pass:
                agree += 1
                mark = "✓"
            else:
                disagree += 1
                mark = "✗"
            print(
                f"  {mark} [{sample['id']}] human={'PASS' if human_pass else 'FAIL'} "
                f"judge={'PASS' if judge_pass else 'FAIL'} — {verdict.get('reasoning', '')[:80]}"
            )
        except Exception as exc:
            errors += 1
            print(f"  ! [{sample['id']}] ERROR: {exc}")

    total = agree + disagree
    rate = agree / total if total > 0 else 0
    print(f"\nAgreement: {agree}/{total} = {rate:.0%}  (target ≥90%)")
    if errors:
        print(f"Errors:    {errors}")

    sys.exit(0 if rate >= 0.90 else 1)


if __name__ == "__main__":
    main()
