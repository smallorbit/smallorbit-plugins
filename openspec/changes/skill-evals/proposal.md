# Skill evals: a tiered evaluation strategy for the plugin suite

## Status

Draft. Authored 2026-06-01. This is a strategy proposal for review **before** any implementation — it defines the evaluation architecture, conventions, and a phased rollout. Spec deltas for the new conventions (a `_shared/eval-authoring.md` and a per-skill `evals/` requirement) are deferred to the implementation change once the approach is approved.

## Problem

The plugins in this monorepo (speckit, swarmkit, polishkit, flowkit, sessionkit, vaultkit, squadkit, opsx-bridge) ship **procedural skills** — SKILL.md runbooks the model executes — plus deterministic `scripts/`. They have no regression safety net for the parts that matter most:

- **The deterministic layer is tested but ungated.** Six skills ship a `scripts/test.sh` (`flowkit/merge-pr`, `flowkit/push-or-pr`, `flowkit/with-clean-workspace`, `swarmkit/clean-remote-worktrees`, `swarmkit/clean-worktrees`, `swarmkit/swarm`), but **no CI runs them**. They execute only when someone remembers to, so they rot silently. The only CI workflow (`deploy-site.yml`) builds the marketing site.
- **The LLM-driven runbook layer has zero evals.** Nothing verifies that a model *following a SKILL.md* makes the right decisions. This is exactly the layer that breaks on a model upgrade, a SKILL.md edit, or a convention change — and it is the layer with real blast radius (git-state mutation, PR creation, label changes).
- **Audit findings recur because nothing freezes them.** The 2026-06-01 cross-plugin audit (epic #1053, PRs #1054–#1061) found a class of drift that will reappear as the repo evolves: stale `develop` references after the single-trunk migration, allowlist entries pointing at removed scripts, citations to moved line numbers, paraphrased-instead-of-cited shared specs, and a silent `claude.flowkit.prBase` pin leak. Each was fixed by hand; none is guarded against recurrence. (`deploy-site.yml` *still* triggers on `develop` — the same drift class, undetected.)
- **Genuinely ambiguous runbook decisions ship untested.** `swarm`'s EPIC_MODE resolution for a single *epic* argument was ambiguous enough during the #1053 swarm that the operator had to reason it out live. Ambiguity in a runbook that nothing pins down is a latent regression.

There is no first-party Anthropic evals harness (confirmed: the canonical reference is Anthropic's *Demystifying evals for AI agents*; teams build their own infra against standardized patterns). So this proposal defines the infrastructure rather than adopting a turnkey one.

## Approach

Adopt a four-layer **eval pyramid**, cheapest and most deterministic at the base, and gate the bottom two layers in CI:

```
        ▲  L4  End-to-end smoke    few · slow · $$$ · nightly      (sandbox repo, real skill)
       ▲▲  L3  Behavioral evals    curated · LLM-in-loop · gated   (fixture + trajectory + judge)
      ▲▲▲  L2  Skill-doc lint      every PR · no LLM · fast        (structure + drift rules)
     ▲▲▲▲  L1  Script unit tests   every PR · deterministic · free (the test.sh you already wrote)
```

- **L1 — Script unit tests.** Formalize the existing `scripts/test.sh` convention; add a discovery runner and a required CI job. Make `test.sh` mandatory for any script-backed skill (the authoring convention already asks for it — this adds the gate).
- **L2 — Skill-doc lint.** A no-LLM linter asserting structural invariants and freezing audit findings as rules: frontmatter present; every `<!-- include: -->`, `_shared/*.md` citation, and relative link resolves; README flag-matrix matches each SKILL.md `## Input`; no stray `develop` branch references outside migration docs; no allowlist entry pointing at a non-existent script. This converts the one-time audit into a permanent ratchet.
- **L3 — Behavioral evals.** Fixture repos as scenarios, the skill run headlessly (`claude -p --output-format stream-json` or the Agent SDK `query()`), and **dual graders**: programmatic assertions on observable state (preferred) plus a calibrated LLM-as-judge for the fuzzy parts (plan correctness, PR-body conformance). Each eval targets **one decision**, seeded from real failures and audit findings.
- **L4 — End-to-end smoke.** A handful of full-flow runs (catalog → swarm → merge-stack) against a throwaway git remote, asserting side effects (issues closed, branches clean, pin unset). Nightly/manual, never per-PR.

**Sequencing:** L1 + L2 land first and run blocking on every PR (deterministic, cheap, and they directly attack the drift class that produced epic #1053). L3 follows for the highest-blast-radius skill (`swarm`: pin lifecycle + EPIC_MODE resolution). L4 last, as a nightly job.

Full architecture, grader design, tooling specifics, determinism/cost controls, and per-layer decisions are in `design.md`. Phased implementation decomposition is in `tasks.md`.

## Non-goals

- Building a bespoke evals framework from scratch when `claude -p` / the Agent SDK + a thin grader layer suffice.
- Putting LLM-in-the-loop evals in the blocking per-PR path (cost + flakiness) — those are gated/nightly.
- Evaluating model quality in the abstract; these evals assert *skill behavior under a pinned model*.
- Replacing the in-skill `## Pre-end self-check` runtime guards — those help at runtime but are not regression evals.
