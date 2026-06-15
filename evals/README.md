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

**L1 and L2 are live** and run as required checks in
[`.github/workflows/skills-ci.yml`](../.github/workflows/skills-ci.yml). L3 and
L4 are forthcoming (see the change's `tasks.md`).

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
