# smallorbit-plugins

[![smallorbit-plugins landing page](docs/assets/landing-hero.png)](https://smallorbit.github.io/smallorbit-plugins/)

## From idea to release. With you in the loop.

Claude Code plugins for plan, execute, and ship — each keeping you at the handoffs that matter.

**[→ View the full landing page](https://smallorbit.github.io/smallorbit-plugins/)**

## Setup

```
/plugin marketplace add smallorbit/smallorbit-plugins
```

## Available Plugins

### Development Lifecycle

| Plugin | Install | Description |
|--------|---------|-------------|
| **speckit** | `/plugin install speckit@smallorbit-plugins` | Define and capture work through interviews and issue filing |
| **swarmkit** | `/plugin install swarmkit@smallorbit-plugins` | Resolve GitHub issues with parallel worktree agents. See [METHODOLOGY.md](./plugins/swarmkit/METHODOLOGY.md) for the stacked agent/PR workflow in depth. For the experimental Agent Teams-based `/squad` variant, see [plugins/swarmkit/SETUP.md](./plugins/swarmkit/SETUP.md). |
| **polishkit** | `/plugin install polishkit@smallorbit-plugins` | Critique code quality, sweep for cruft, and eliminate dead code |
| **flowkit** | `/plugin install flowkit@smallorbit-plugins` | Manage the full git lifecycle from branch to release |
| **sessionkit** | `/plugin install sessionkit@smallorbit-plugins` | Session continuity, context handoffs, and meta-learning |
| **metakit** _(pre-release 0.1.0)_ | `/plugin install metakit@smallorbit-plugins` | Dynamic orchestrator that composes sibling kits into multi-step scenarios with graceful degradation |

### Utilities & Productivity

| Plugin | Install | Description |
|--------|---------|-------------|
| **vaultkit** | `/plugin install vaultkit@smallorbit-plugins` | Obsidian vault skills — read, search, edit notes, and capture decisions |

## How the Plugins Compose

The development-lifecycle plugins form a complete loop from idea to release:

```
/interview     → clarify the idea (speckit)
/spec          → plan the feature, file issues (speckit)
/swarm         → resolve issues with parallel agents (swarmkit)
/critique      → assess quality; /tidy-codebase to clean up (polishkit)
/release       → ship merged work to production (flowkit)
```

**sessionkit** acts as connective tissue throughout: use `/handoff` to preserve state across agent context limits, `/skillit` to capture reusable patterns after a swarm, and `/suggest-permissions` to reduce approval friction over time.

**metakit** (pre-release) sits above the loop as the recommended entry point for multi-kit workflows. Rather than chaining commands by hand, prefer:

- `/polish-cycle` — drives polishkit's critique → speckit's catalog → swarmkit's swarm in one command, pausing for confirmation on risky steps and skipping missing kits gracefully
- `/handoff-cycle` — auto-infers inputs and walks vaultkit's archive-export → vaultkit's jot → sessionkit's handoff so session close-out is a single command
- `/kits` — reports which sibling kits are installed and which metakit scenarios are fully vs. partially runnable in the current environment

metakit detects installed kits at runtime, previews the plan before acting, skips missing steps rather than failing, and halts with a state report on any failure.

**vaultkit** lives outside the loop — it's a utility for capturing decisions, notes, and archives into an Obsidian vault alongside any work, dev or otherwise. Requires Obsidian and the Obsidian CLI.

Each plugin's README describes how it pairs with the others.

See each plugin's README for detailed usage.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.

## License

MIT — see [LICENSE](./LICENSE).
