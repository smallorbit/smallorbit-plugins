# Judge calibration

The LLM-as-judge in `evals/graders/judge.py` grades fuzzy assertions — PR body
conformance, plan correctness. Before trusting verdicts in production CI, validate
that the judge agrees with human labels on a representative sample.

## When calibration is required

- Before adding `pr_body_conformance.py` to the blocking nightly gate.
- After changing the judge model (`JUDGE_MODEL` in `judge.py`).
- After updating the rubric passed to `judge()`.

## Protocol

1. **Review `samples.jsonl`.** Each line is a JSON object with:
   - `id` — unique sample ID
   - `type` — eval type (`pr_body_conformance`, …)
   - `content` — the text being judged
   - `suggested_label` — `true` (PASS) or `false` (FAIL) with a rationale
   - `human_label` — initially `null`; set this after your review
   - `human_notes` — optional free-text reasoning

2. **Label each sample.** Open `samples.jsonl` and fill in `human_label` for every
   entry where it is `null`. Expected effort: ~30 minutes for the 25 samples here.

3. **Run agreement check.**
   ```bash
   ANTHROPIC_API_KEY=... python3 evals/calibration/check_agreement.py
   ```
   This runs the judge on every labeled sample and reports agreement rate.
   Target: ≥90% agreement before using the judge in CI.

4. **Iterate.** If agreement is below 90%:
   - Read the disagreements — they usually cluster around a rubric ambiguity.
   - Tighten the rubric in `judge.py` (or the eval that calls it).
   - Re-run until the target is met.

5. **Sign off.** Once the target is met, commit the labeled `samples.jsonl` and
   note the agreement rate in a comment in `judge.py`.

## Sample coverage

`samples.jsonl` contains 25 PR body conformance cases seeded from:
- The pr-body.md worked example (PASS)
- Violations found in the 2026-06-01 cross-plugin audit
- Synthetic edge cases (missing sections, wrong keywords, multi-ref on one line)

The `suggested_label` is the expected correct answer based on pr-body.md — it is
NOT a pre-validated ground truth. Human review determines the actual label.
