# smallorbit-plugins

A collection of plugins for Claude Code.

## Setup

```
/plugin marketplace add smallorbit/smallorbit-plugins
```

## Available Plugins

| Plugin | Install | Description |
|--------|---------|-------------|
| **swarmkit** | `/plugin install swarmkit@smallorbit-plugins` | Spec, swarm, and ship GitHub issues with parallel agents |

See each plugin's README for detailed usage.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.
