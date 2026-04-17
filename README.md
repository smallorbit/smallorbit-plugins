# smallorbit-plugins

A collection of plugins for Claude Code.

**[→ One-page Overview](https://smallorbit.github.io/smallorbit-plugins/)**

## Setup

```
/plugin marketplace add smallorbit/smallorbit-plugins
```

## Available Plugins

| Plugin | Install | Description |
|--------|---------|-------------|
| **swarmkit** | `/plugin install swarmkit@smallorbit-plugins` | Resolve GitHub issues with parallel worktree agents |
| **flowkit** | `/plugin install flowkit@smallorbit-plugins` | Manage the full git lifecycle from branch to release |
| **speckit** | `/plugin install speckit@smallorbit-plugins` | Define and capture work through interviews and issue filing |
| **sessionkit** | `/plugin install sessionkit@smallorbit-plugins` | Session continuity, context handoffs, and meta-learning |

## How the Plugins Compose

The four plugins form a complete development loop:

```
/interview     → clarify the idea (speckit)
/spec          → plan the feature, file issues (speckit)
/swarm         → resolve issues with parallel agents (swarmkit)
/release       → ship merged work to production (flowkit)
```

**sessionkit** acts as connective tissue throughout: use `/handoff` to preserve state across agent context limits, `/skillit` to capture reusable patterns after a swarm, and `/suggest-permissions` to reduce approval friction over time.

Each plugin's README describes how it pairs with the others.

See each plugin's README for detailed usage.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.
