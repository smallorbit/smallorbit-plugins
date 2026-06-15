# Skill evals

A tiered evaluation strategy for the plugin suite. Cheapest and most
deterministic layers gate every PR; LLM-in-loop layers run off the blocking
path. Full strategy: `openspec/changes/skill-evals/` (proposal, design, tasks).

```
        ▲  L4  End-to-end smoke    few · slow · nightly        (sandbox repo, real skill)
       ▲▲  L3  Behavioral evals    curated · LLM-in-loop        (fixture + trajectory + judge)
      ▲▲▲  L2  Skill-doc lint      every PR · no LLM · fast     (structure + drift rules)
     ▲▲▲▲  L1  Script unit tests   every PR · deterministic     (the test.sh you already wrote)
```

**L1 and L2** run as required checks in
[`.github/workflows/skills-ci.yml`](../.github/workflows/skills-ci.yml).
**L3** runs nightly in
[`.github/workflows/evals-nightly.yml`](../.github/workflows/evals-nightly.yml).
**L4** (end-to-end smoke) is stubbed in the nightly workflow — requires the
`SMALLORBIT_TEST_ORG_TOKEN` secret and test-org provisioning (see § L4 below).

## L1 — Script unit tests

Discovers and runs every `plugins/*/skills/*/scripts/test.sh`, failing on any
non-zero exit.

```bash
scripts/test-all-skill-scripts.sh
```

`test.sh` is **mandatory** for any script-backed skill — see
[`plugins/_shared/script-authoring.md`](../plugins/_shared/script-authoring.md#smoke-tests)
for the contract (invalid-arg coverage, JSON happy paths, network-dependent
limitations).

## L2 — Skill-doc lint

A no-LLM structural linter over `plugins/**` and root docs. Each rule reports a
`file:line`. It freezes the 2026-06-01 cross-plugin audit findings as permanent
ratchets.

```bash
python3 scripts/lint-skills.py            # report; fail only on ERROR
python3 scripts/lint-skills.py --strict   # fail on WARN too
```

### Severity policy

- **ERROR** — high-confidence structural violation; fails the gate (exit 1).
- **WARN** — fuzzy/heuristic signal; reported but non-blocking, until proven
  low-false-positive and promoted to ERROR.

This split keeps the gate trustworthy: a flaky or noisy rule never blocks a
merge. Promote a WARN rule to ERROR once it runs clean across the tree.

### Rule catalog

| Rule | Severity | Catches |
|------|----------|---------|
| `frontmatter` | ERROR | SKILL.md missing the `---` block or its `name:`/`description:` fields |
| `include` | ERROR | `<!-- include: <path> -->` directive whose target does not resolve (repo-root or file-relative) |
| `link` | ERROR | relative markdown link whose target file does not exist (anchors/externals/code-fences skipped) |
| `shared-citation` | ERROR | a `plugins/_shared/*.md` citation path that does not exist |
| `develop` | ERROR | a stale `develop` branch reference outside the migration/legacy allowlist (incl. `.github/workflows/**`) |
| `allowlist` | ERROR | a `.claude/settings.json` permission entry pointing at a non-existent `plugins/**.sh` script |
| `input-table` | WARN | a SKILL.md that documents `` `--flags` `` in prose but has no Input/Arguments/Flags heading |
| `flag-matrix` | WARN | a SKILL.md flag absent from its plugin README (coarse drift heuristic) |
| `paraphrase` | WARN | a doc that inlines the PR-body section shape without citing `_shared/pr-body.md` |

### Notes on specific rules

**`develop`.** A single-trunk repo (`main`) has no `develop` branch, so live
references are drift. But many `develop` mentions are legitimate: the v3→v4
migration surfaces, v3 legacy-detection guards, and negative phrasings ("there
is no develop"). The rule flags only references that *look like a live branch
target* and are not covered by:

- the file allowlist in `lint-skills.py` (`DEVELOP_FILE_ALLOWLIST` — migration
  and legacy-detection docs),
- a negative-context phrasing (`no`/`never`/`not`/`without` near `develop`, or
  `develop` next to `intermediary`/`split`/`probe`, or a `develop|main`
  branch-protection alternation),
- an inline `lint-allow-develop` marker on the line.

**`flag-matrix`.** A coarse heuristic: it extracts only backtick-wrapped
`` `--flag` `` tokens from SKILL.md prose (ignoring CLI flags inside shell
snippets) and warns when one is absent from the plugin README. It surfaces real
drift but also soft positives (a flag mentioned only to say it is *not* used), so
it is WARN, not ERROR.

## Adding a rule

1. Add a `rule_<name>(findings)` function in `scripts/lint-skills.py` that
   appends `Finding(severity, path, line, rule, message)` entries. Reuse the
   `prose_lines()` / `documented_flags()` helpers to skip fenced code blocks.
2. Register it in the `RULES` tuple.
3. Start at `WARN`. Run `python3 scripts/lint-skills.py` against the full tree;
   if it is clean (no false positives), promote to `ERROR`.
4. Document it in the rule catalog above.

Every new statically-checkable audit finding should become a rule here — that is
how the one-time audit becomes a permanent ratchet.

## L3 — Behavioral evals

Decision-probe evals for high-blast-radius runbook decisions. Each file targets
one decision; the model reads a SKILL.md excerpt and answers structured JSON.

```bash
ANTHROPIC_API_KEY=... python3 evals/l3/swarm/epic_mode_single_arg.py
ANTHROPIC_API_KEY=... python3 evals/l3/swarm/prbase_pin_lifecycle.py
ANTHROPIC_API_KEY=... python3 evals/l3/swarm/dag_topo_order.py
ANTHROPIC_API_KEY=... python3 evals/l3/swarm/pr_body_conformance.py

ANTHROPIC_API_KEY=... python3 evals/l3/catalog/closes_multiref.py
ANTHROPIC_API_KEY=... python3 evals/l3/catalog/split_decision.py
```

Or run them all via the nightly workflow locally:

```bash
ANTHROPIC_API_KEY=... act -j l3-swarm -j l3-catalog
```

### Prerequisites

```bash
pip install anthropic==0.40.0
export ANTHROPIC_API_KEY=<key>
```

### Eval catalog

| File | Skill | Decision asserted |
|------|-------|-------------------|
| `l3/swarm/epic_mode_single_arg.py` | swarm | Single epic arg → EPIC_MODE=on; standalone → off |
| `l3/swarm/prbase_pin_lifecycle.py` | swarm | prBase unset on all exit paths |
| `l3/swarm/dag_topo_order.py` | swarm | Blocked issue processed after its parent |
| `l3/swarm/pr_body_conformance.py` | swarm (judge) | PR body conforms to pr-body.md |
| `l3/catalog/closes_multiref.py` | catalog | One Closes per line; Refs for parent epics |
| `l3/catalog/split_decision.py` | catalog | Consolidation vs --split decision |

### Judge calibration

`pr_body_conformance.py` uses the LLM-as-judge. Before trusting its verdicts in CI,
calibrate the judge against the 25 labeled samples in `evals/calibration/`:

```bash
# 1. Fill in human_label in evals/calibration/samples.jsonl
# 2. Run agreement check (target ≥90%)
ANTHROPIC_API_KEY=... python3 evals/calibration/check_agreement.py
```

See `evals/calibration/README.md` for the full protocol.

### Adding a new L3 eval

1. Identify ONE decision in a high-blast skill.
2. Create a fixture JSON in `evals/fixtures/` if mock gh data is needed.
3. Write `evals/l3/<skill>/<decision>.py` using the `decision_probe()` helper.
4. Add the script to the matching job in `.github/workflows/evals-nightly.yml`.
5. Document it in the eval catalog above.
6. If judge-graded: add calibration samples and verify ≥90% agreement.

Convention: `plugins/_shared/eval-authoring.md`.

## L4 — End-to-end smoke

Planned — requires a dedicated test-org GitHub repo. The nightly workflow has a
commented-out `l4-smoke` job. To enable:

1. Create a test GitHub org and repo (separate from production).
2. Add a `SMALLORBIT_TEST_ORG_TOKEN` secret with `repo` scope to that repo only.
3. Add a `SMALLORBIT_TEST_ORG_REPO` variable (e.g. `my-test-org/swarm-smoke`).
4. Write `evals/l4/smoke.py` with a reset/seed step + full-flow assertion.
5. Uncomment the `l4-smoke` job in `evals-nightly.yml`.

The smoke runs: catalog → swarm → merge-stack on a tiny fixture, asserting issues
are closed, branches deleted, pin clean, and epic closed after the run.
