---
name: ship
description: Full one-shot ship cycle — branch → commit → PR → merge → RC → release. Runs the complete flowkit pipeline from wherever you are on a branch.
triggers:
  - "/ship"
  - "ship this"
  - "ship it"
  - "ship the work"
  - "full ship cycle"
allowed-tools: Bash
---

# Ship

Run the full release pipeline from current branch state to a tagged release on main. Handles branching, committing, opening/merging a PR, cutting an RC, and releasing.

## Input

`$ARGUMENTS` — optional description or context passed to `/open-pr` as the PR description. If omitted, the PR description is inferred from commits.

## Process

### 1. Scope the PR base

Follow the `pr-base-scope` sub-skill to set `claude.prBase = develop`. This ensures all PR operations in this pipeline target `develop`.

### 2. Get work onto develop via PR

Detect the current state and act accordingly:

- **On `develop`, `main`, or `staging`**: follow `/pr $ARGUMENTS` — this will create a branch, commit, and open a PR targeting develop.
- **On a feature branch with uncommitted changes**: follow `/commit`, then follow `/open-pr`.
- **On a feature branch with an open PR already**: skip directly to step 3.
- **On a feature branch, changes committed, no open PR**: follow `/open-pr`.

### 3. Merge the PR into develop

Follow `/merge-pr` to squash-merge the open PR into `develop`.

### 4. Sync develop

Follow `/sync` to check out `develop`, pull latest, and prune stale branches.

### 5. Cut a release candidate

Follow `/cut` to create an `rc/YYYY-MM-DD.N` branch from `origin/develop`. If `origin/staging` exists, `/cut` will auto-stage it.

### 6. Release

Follow `/release` to merge to `main`, create the version tag, close referenced issues, and clean up RC branches.

### 7. Unset the PR base scope

Follow the `pr-base-scope` sub-skill to unset `claude.prBase`.

### 8. Report

Summarize what happened:
- Which PR was merged and into which base
- Which RC was created
- Which tag was created on main
- Which issues were closed

## Constraints

- Always set `claude.prBase` at the start and unset it at the end — never leave it set
- No self-review step — `/ship` is a pipeline, not a quality gate
- If any step fails, stop immediately and report what failed and why — do not attempt to continue past a failure
- Never commit directly to `develop` or `main`
