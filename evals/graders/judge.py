"""LLM-as-judge grader for L3 behavioral evals.

Wraps claude-sonnet-4-6 as a structured judge for fuzzy assertions —
plan correctness, PR body conformance — where programmatic assertions
are insufficient.

Calibration: before trusting verdicts in CI, run `evals/calibration/`
to validate the judge against hand-labeled samples. See
`evals/calibration/README.md` for the calibration protocol.

Prerequisites:
  pip install anthropic
  ANTHROPIC_API_KEY in environment
"""

from __future__ import annotations

import json
import os

JUDGE_MODEL = "claude-sonnet-4-6"
JUDGE_MAX_TOKENS = 512
DEFAULT_BUDGET_USD = 0.10


def judge(
    content: str,
    rubric: str,
    model: str = JUDGE_MODEL,
    budget_usd: float = DEFAULT_BUDGET_USD,
) -> dict:
    """Evaluate `content` against `rubric`.

    Returns a dict with keys:
      passed  (bool)   — True only if ALL rubric criteria are met
      verdict (str)    — "PASS" or "FAIL"
      reasoning (str)  — brief explanation; cite the violation on FAIL

    Raises RuntimeError if cost exceeds `budget_usd`.
    """
    try:
        import anthropic
    except ImportError:
        raise ImportError(
            "The 'anthropic' package is required for L3 judge evals. "
            "Install it with: pip install anthropic"
        )

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError("ANTHROPIC_API_KEY environment variable is not set.")

    client = anthropic.Anthropic(api_key=api_key)

    system = (
        "You are a strict technical reviewer. Default to FAIL — pass only if ALL "
        "rubric criteria are met with no exceptions. Be concise. "
        "Respond with valid JSON only: "
        '{"passed": bool, "verdict": "PASS" or "FAIL", "reasoning": "one sentence"}'
    )

    user = f"## Content\n\n{content}\n\n## Rubric\n\n{rubric}"

    response = client.messages.create(
        model=model,
        max_tokens=JUDGE_MAX_TOKENS,
        system=system,
        messages=[{"role": "user", "content": user}],
    )

    cost = (
        response.usage.input_tokens * 3 + response.usage.output_tokens * 15
    ) / 1_000_000
    if cost > budget_usd:
        raise RuntimeError(
            f"Judge budget exceeded: ${cost:.4f} > ${budget_usd:.4f} allowed"
        )

    text = response.content[0].text.strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()

    result = json.loads(text)
    # Normalize passed to bool
    result["passed"] = bool(result.get("passed", False))
    return result
