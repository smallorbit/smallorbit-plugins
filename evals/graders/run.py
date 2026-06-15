"""Decision-probe runner for L3 behavioral evals.

Invokes the Anthropic API directly (not via claude CLI) to run a
"decision probe": give the model a SKILL.md excerpt as context, describe
a specific scenario, and ask it to make ONE decision as structured JSON.
This is cheaper and more deterministic than full headless skill execution
while still catching regressions in runbook comprehension.

Prerequisites:
  pip install anthropic
  ANTHROPIC_API_KEY in environment

For full headless execution evals (future), use `claude -p --output-format
stream-json --verbose --bare` and parse the tool_use events.
"""

from __future__ import annotations

import json
import os

PROBE_MODEL = "claude-sonnet-4-6"
DEFAULT_BUDGET_USD = 0.05


def decision_probe(
    system: str,
    prompt: str,
    response_schema_desc: str,
    model: str = PROBE_MODEL,
    budget_usd: float = DEFAULT_BUDGET_USD,
) -> dict:
    """Run a decision probe. Returns parsed JSON from the model.

    The model receives `system` as the system prompt (typically the relevant
    SKILL.md section) and `prompt` as the user turn (scenario + JSON instruction).

    Raises RuntimeError if the actual API cost exceeds `budget_usd`.
    Raises ValueError if the model returns non-JSON.
    Raises ImportError if the `anthropic` package is not installed.
    """
    try:
        import anthropic
    except ImportError:
        raise ImportError(
            "The 'anthropic' package is required for L3 evals. "
            "Install it with: pip install anthropic"
        )

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError("ANTHROPIC_API_KEY environment variable is not set.")

    client = anthropic.Anthropic(api_key=api_key)

    full_system = (
        f"{system}\n\n"
        "Always respond with valid JSON — no prose, no markdown fences. "
        f"Schema: {response_schema_desc}"
    )

    response = client.messages.create(
        model=model,
        max_tokens=512,
        system=full_system,
        messages=[{"role": "user", "content": prompt}],
    )

    # Rough cost check (sonnet-4-6: $3/MTok input, $15/MTok output)
    cost = (
        response.usage.input_tokens * 3 + response.usage.output_tokens * 15
    ) / 1_000_000
    if cost > budget_usd:
        raise RuntimeError(
            f"Budget exceeded: ${cost:.4f} > ${budget_usd:.4f} allowed"
        )

    text = response.content[0].text.strip()
    # Strip accidental markdown fences
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Model returned non-JSON: {text!r}"
        ) from exc
