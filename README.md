# smallorbit-plugins

A collection of plugins for Claude Code.

**[→ One-page Overview](https://smallorbit.github.io/smallorbit-plugins/)**

## Setup

```
/plugin marketplace add smallorbit/smallorbit-plugins
```

## Available Plugins

### Development Lifecycle

| Plugin | Install | Description |
|--------|---------|-------------|
| **speckit** | `/plugin install speckit@smallorbit-plugins` | Define and capture work through interviews and issue filing |
| **swarmkit** | `/plugin install swarmkit@smallorbit-plugins` | Resolve GitHub issues with parallel worktree agents |
| **polishkit** | `/plugin install polishkit@smallorbit-plugins` | Critique code quality, sweep for cruft, and eliminate dead code |
| **flowkit** | `/plugin install flowkit@smallorbit-plugins` | Manage the full git lifecycle from branch to release |
| **sessionkit** | `/plugin install sessionkit@smallorbit-plugins` | Session continuity, context handoffs, and meta-learning |

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

**vaultkit** lives outside the loop — it's a utility for capturing decisions, notes, and archives into an Obsidian vault alongside any work, dev or otherwise. Requires Obsidian and the Obsidian CLI.

Each plugin's README describes how it pairs with the others.

See each plugin's README for detailed usage.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.
