---
title: "Stacked PRs without the headache"
subtitle: "How swarmkit dispatches isolated agents and merges their work top-down"
kit: swarmkit
date: 2026-04-22
author: smallorbit
readTime: 8
draft: false
tags: ["swarmkit", "workflow", "stacked-prs"]
---

A swarm produces a stack of dependent pull requests. Merging that stack without
breaking the dependency order is the difference between a clean release and a
weekend of cherry-picks.

## The shape of the stack

When you dispatch `/swarm` against a list of issues, swarmkit picks a root issue,
opens a branch off `develop`, and stacks the rest of the PRs on top — each one
targeting the branch above it. The dependency graph is encoded directly in the
GitHub PR base-branch field, so reviewers can see what depends on what.

## Merging top-down

`/merge-stack` walks the stack leaf-first, retargets every non-root PR to the
base branch in one batch, and squash-merges with `--delete-branch`. The result:
one squash commit per issue on `develop`, no merge bubbles, and no orphaned
remote branches.

## Where this draft picks up

This post will become a long-form walkthrough. For now it exists as a fixture
that demonstrates the kit-aggregation page at `/kits/swarmkit/`.
