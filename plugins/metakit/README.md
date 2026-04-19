# metakit

A Claude Code plugin that composes sibling kits into multi-step scenarios. metakit detects which kits are installed at runtime, renders a plan preview, skips missing steps, pauses on risky ones for confirmation, and halts with a state report on failure — so the same command does the right thing whether you have the full suite or just a subset.

> **Status:** pre-release (v0.1.0). The scenarios below are shipping alongside this release; see each section for what's wired up today.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install metakit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/metakit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- One or more sibling kits from `smallorbit-plugins` (speckit, swarmkit, polishkit, flowkit, sessionkit, vaultkit). metakit detects what's available and degrades gracefully when kits are missing.

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **kits** | `/kits` | Report which sibling kits are installed, at what version, and which metakit scenarios are fully vs. partially runnable in the current environment. |
| **polish-cycle** | `/polish-cycle` | Run the quality loop: polishkit's `/critique` to surface findings, speckit's `/catalog` to file them as issues, and swarmkit's `/swarm` to resolve them — pausing for confirmation on the risky steps. |
| **handoff-cycle** | `/handoff-cycle` | Close out a session cleanly: vaultkit's `/archive-export` to archive the conversation, vaultkit's `/jot` to capture decisions, and sessionkit's `/handoff` to write the handoff document — with inputs auto-inferred where possible. |

## Scenarios

Each scenario follows the same shape: detect installed kits → render a plan preview with each step marked runnable/skipped → execute runnable steps in order, pausing on risky ones for confirmation → halt with a state report on failure.

### /kits — discovery

Reports the current kit landscape from inside Claude Code, so you never have to spelunk through `settings.json` to answer "what's installed and what can I run?".

**Inputs**

- None required.
- Optional: a kit name (e.g. `/kits speckit`) to drill into a single kit's skills and version.

**What it renders**

1. A table: `| Kit | Version | Scope | Skills | Status |` listing every sibling kit metakit looked for, with its resolved version, whether it was discovered in user scope, project scope, or both, the user-facing skills it exposes, and an `enabled` / `disabled` / `not installed` status.
2. Below the table, every metakit scenario marked as `full` (all required kits present), `partial (missing: X, Y)` (some steps will be skipped), or `unavailable` (no runnable steps).

**Risk**

- Read-only. `/kits` never modifies state — no pauses, no confirmations.

### /polish-cycle — the quality loop

Automates the repeated multi-kit workflow of assessing, cataloguing, and resolving quality findings. The scenario sequence:

1. **`polishkit:critique`** — scored quality assessment across five dimensions. Produces a report. *Low risk — runs without a pause.*
2. **`speckit:catalog`** — converts the critique findings into prioritized, labeled GitHub issues. *Risky (files issues on your repo) — pauses for confirmation with the filing plan.*
3. **`swarmkit:swarm`** — spawns parallel isolated-worktree agents to resolve the new issues and open PRs. *Risky (creates worktrees, branches, and PRs) — pauses for confirmation with the swarm plan.*

**Graceful degradation**

- If **polishkit** is missing, the scenario is `unavailable` — nothing to critique, nothing downstream to file. metakit reports that and exits.
- If **speckit** is missing, the critique still runs; metakit reports the findings inline and surfaces that `catalog` and `swarm` cannot proceed without speckit.
- If **swarmkit** is missing, critique + catalog still run; metakit surfaces that resolution would have happened via swarm and that you can run swarmkit's `/swarm` manually later against the filed issues.

**Risk profile**

| Step | Risk | Pause |
|------|------|-------|
| critique | low | no |
| catalog | risky (files issues) | yes |
| swarm | risky (opens PRs) | yes |

### /handoff-cycle — session close-out

A single command to wrap up a session cleanly. The scenario sequence:

1. **`vaultkit:archive-export`** — archives the current conversation export into the active vault project. *Risky (writes a vault file) — pauses for confirmation.*
2. **`vaultkit:jot`** — captures a one-line session summary into the vault as a decision/note. *Risky (appends a vault file) — pauses for confirmation.*
3. **`sessionkit:handoff`** — writes the handoff document so another agent can pick up seamlessly. *Risky (writes handoff file) — pauses for confirmation.*

**Auto-inferred inputs**

- **Vault project** — resolved via vaultkit's active-project detection.
- **Session summary** — synthesised from recent conversation turns (one line).
- **Handoff destination** — sessionkit's default path.

metakit asks the user only when inference is ambiguous (e.g. no active vault project detected, multiple candidates present).

**Graceful degradation**

- If **vaultkit** is missing, the first two steps are marked skipped; sessionkit's handoff still runs and metakit reports that no vault archive or jot was captured.
- If **sessionkit** is missing, the vault steps still run; metakit reports that no handoff document was written.
- If both are missing, the scenario is `unavailable` and metakit exits after the preview.

**Risk profile**

| Step | Risk | Pause |
|------|------|-------|
| archive-export | risky (writes vault file) | yes |
| jot | risky (appends vault file) | yes |
| handoff | risky (writes handoff file) | yes |

## Hybrid-Execution Model

metakit is an orchestrator, not an executor. Scenarios run in two distinct modes depending on the step:

- **Detection and planning (in-process)** — reading `settings.json`, resolving installed kits, rendering the plan preview, and auto-inferring inputs all happen inside the metakit skill directly. No sub-agent, no tool hop.
- **Step execution (delegated)** — each scenario step is dispatched via the **Skill** tool to the target kit's skill (e.g. `polishkit:critique`, `speckit:catalog`, `swarmkit:swarm`). The target skill runs with its own context and reports back.

This split matters because:

1. **The orchestrator stays cheap.** Detection and preview are inexpensive — they don't need a fresh context, and running them in-process means `/kits` and the preview step of every scenario are near-instant.
2. **Step execution gets its own context budget.** Delegating via Skill means each step gets a clean surface to work on without the orchestrator's history dominating its window. A swarm or a long critique doesn't have to share tokens with the preview it came from.
3. **Halting is well-defined.** Because each step is a discrete Skill invocation, metakit can observe its completion or failure and decide whether to continue or halt — without needing to interpret free-form sub-agent output.

## Halt-and-Report Failure Contract

Every metakit scenario honors the same failure contract. When any step fails — the underlying skill errors, the user declines a confirmation, a required tool is unavailable — metakit does **not** continue to the next step. It halts and emits a state report with:

- **What ran** — each step that completed successfully, in order, with any outputs worth recording (issue numbers filed, PR URLs opened, handoff paths written).
- **What didn't** — the step that failed, the failure reason (error message, declined confirmation, missing dependency), and every downstream step that was consequently skipped.
- **Resume guidance** — the minimum context another agent (or you in a later session) needs to continue: which skill to re-invoke, which inputs are already resolved, which preconditions still need to hold.

The contract is intentionally conservative: metakit never silently skips a failed step and never tries to "recover" by substituting a different step. If the plan can't run as previewed, the scenario stops and surfaces enough state to resume by hand.

**Not the same as graceful degradation.** Degradation happens *before* execution, during the preview — a step is marked skipped because the required kit isn't installed, and the remaining steps run normally. Halt-and-report happens *during* execution — a step that was expected to run actually failed, so everything after it is held back.

## Graceful-Degradation Contract

Every metakit scenario follows the same shape:

1. **Detect** which sibling kits are installed (see `/kits` for the mechanism).
2. **Preview** the plan — show the ordered step list and mark any steps that will be skipped because the required kit is missing.
3. **Skip missing steps** silently after the preview is approved; never fail because a kit isn't present.
4. **Pause on risky steps** (destructive operations, PR merges, releases) for explicit confirmation.
5. **Halt on failure** with a state report — see "Halt-and-Report Failure Contract" above.

This means `/polish-cycle` works whether you have all of polishkit + speckit + swarmkit or just polishkit — the scenario adapts to what's available instead of refusing to run.

## Pairing with Other Plugins

metakit is an orchestrator — it doesn't replace any sibling kit, it composes them:

- **[speckit](../speckit)** — `/polish-cycle` files critique findings as issues via `/catalog`.
- **[swarmkit](../swarmkit)** — `/polish-cycle` hands filed issues off to `/swarm` for parallel resolution.
- **[polishkit](../polishkit)** — `/polish-cycle` drives `/critique` as the first step in the quality loop.
- **[flowkit](../flowkit)** — metakit scenarios defer to flowkit for PR, cut, and release operations.
- **[sessionkit](../sessionkit)** — `/handoff-cycle` uses `/handoff` as its terminal step.
- **[vaultkit](../vaultkit)** — `/handoff-cycle` uses `/archive-export` and `/jot` to persist session state into the active Obsidian vault.
