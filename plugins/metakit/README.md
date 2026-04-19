# metakit

A Claude Code plugin that composes sibling kits into multi-step scenarios. metakit detects which kits are installed at runtime, renders a plan preview, skips missing steps, pauses on risky ones for confirmation, and halts with a state report on failure — so the same command does the right thing whether you have the full suite or just a subset.

> **Status:** early scaffold (v0.1.0). The plugin shell exists; the scenario skills below are coming soon.

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
| **kits** | `/kits` | _Coming soon._ Report which sibling kits are installed and what scenarios are currently runnable. |
| **polish-cycle** | `/polish-cycle` | _Coming soon._ Run a full quality pass — critique, dead-code sweep, tidy — then file findings as issues and optionally swarm fixes. |
| **handoff-cycle** | `/handoff-cycle` | _Coming soon._ Close out a session cleanly — capture state, suggest skills worth keeping, archive decisions into the vault if present. |

## Graceful-Degradation Contract

Every metakit scenario follows the same shape:

1. **Detect** which sibling kits are installed.
2. **Preview** the plan — show the ordered step list and mark any steps that will be skipped because the required kit is missing.
3. **Skip missing steps** silently after the preview is approved; never fail because a kit isn't present.
4. **Pause on risky steps** (destructive operations, PR merges, releases) for explicit confirmation.
5. **Halt on failure** with a state report — what ran, what didn't, what the next agent needs to know to resume.

This means `/polish-cycle` works whether you have all of polishkit + speckit + swarmkit or just polishkit — the scenario adapts to what's available instead of refusing to run.

## Pairing with Other Plugins

metakit is an orchestrator — it doesn't replace any sibling kit, it composes them:

- **[speckit](../speckit)** — metakit scenarios file findings as issues via `/issue` or `/catalog`.
- **[swarmkit](../swarmkit)** — metakit scenarios can hand filed issues off to `/swarm` for parallel resolution.
- **[polishkit](../polishkit)** — `/polish-cycle` drives `/critique`, `/dead-code`, and `/tidy-codebase` in sequence.
- **[flowkit](../flowkit)** — metakit scenarios defer to flowkit for PR, cut, and release operations.
- **[sessionkit](../sessionkit)** — `/handoff-cycle` uses `/handoff` and `/skillit` to capture and carry state.
- **[vaultkit](../vaultkit)** — when present, metakit scenarios can archive plans and decisions via `/jot` or `/archive-export`.
