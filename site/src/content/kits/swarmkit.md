---
name: swarmkit
role: Execute it — parallel worktree agents resolving issues into stacked PRs
oneLiner: Resolve GitHub issues with parallel agents — pick what to work on, swarm it in isolated worktrees, merge top-down.
commands:
  - /swarmkit:swarm
  - /swarmkit:swarm-plus
  - /swarmkit:next-issue
  - /swarmkit:merge-stack
  - /swarmkit:clean-worktrees
  - /swarmkit:clean-remote-worktrees
summary: >
  swarmkit dispatches one isolated-worktree agent per issue, opens stacked PRs
  in dependency order, and lets you merge them bottom-up with a single command.
  An optional /swarm-plus layer adds an automatic reviewer plus one fix-up pass
  per PR. Read METHODOLOGY.md for the full stacked-agent / stacked-PR design.
---

swarmkit is the parallel-execution engine — issues in, stacked PRs out.
