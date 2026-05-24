---
name: ship-epic
description: Promote a long-lived feature/<slug>-<N> epic to develop via rebase-merge, unset claude.flowkit.prBase, delete the epic branch, and fast-forward develop. Closer for flowkit:cut-epic.
triggers:
  - "/ship-epic"
  - "ship the epic"
  - "close out epic"
  - "promote feature branch to develop"
allowed-tools: Bash
---

# Ship Epic

Promote a long-lived `feature/<slug>-<N>` epic branch to `develop` via rebase-merge, clear the session scope, and delete the epic branch. The symmetric closer for `flowkit:cut-epic`.

After this skill runs: `develop`'s first-parent line stays linear (one squashed commit per merged feature, no octopus or back-merge bubbles), `claude.flowkit.prBase` is cleared, and the local epic branch is gone.

## Input

`$ARGUMENTS` — optional. Either:

1. `--epic <branch>` — explicit epic branch override. Must start with `feature/` and must not equal `develop`, `main`, or `master`.
2. Empty — resolved from `git config --get claude.flowkit.prBase`. If unset or equal to `develop`, the skill stops:

> No epic in flight. `claude.flowkit.prBase` is unset (or equals `develop`) and no `--epic` flag was passed. Run `/cut-epic` first, pass `--epic <branch>`, or check out the epic branch.

## Process

### 1. Capture `$SKILL_DIR`

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
```

### 2. Run the script

```bash
RESULT=$(bash "$SKILL_DIR/scripts/ship_epic.sh" $ARGUMENTS)
```

The script handles: epic resolution, push, preflight guardrails, closes-token aggregation, PR creation, rebase-merge via `with-clean-workspace`, config unset, and local develop fast-forward.

### 3. On success

If `RESULT` is non-empty JSON, report:

> Shipped epic `<epic_branch>` to develop via PR #`<pr_number>`. `claude.flowkit.prBase` cleared. Local develop fast-forwarded.

Include the PR URL from `result.pr_url`. If `result.develop_advanced` is `false`, note:

> Local develop was not fast-forwarded (operator is on a different worktree). Run `/sync` to pull develop.

### 4. On failure

If the script exits non-zero (empty stdout), surface stderr and stop. Do not retry — the error message includes a recovery hint.

## Output

| Field | Type | Description |
|-------|------|-------------|
| `epic_branch` | string | The promoted branch, e.g. `feature/onboarding-v2-1264`. |
| `pr_number` | number | Epic-to-develop PR number. |
| `pr_url` | string | Full PR URL. |
| `closes_tokens` | array of strings | Closing-keyword lines aggregated from child squash commits, merged child PR bodies (in case `gh pr merge --squash` dropped the token from the commit message), and the epic issue ref. De-duped case-insensitively. |
| `pr_base_unset` | boolean | `true` if `claude.flowkit.prBase` was set and cleared; `false` if it was already unset. |
| `develop_advanced` | boolean | `true` if local develop fast-forwarded; `false` if the operator is on a different worktree (local develop ref was not touched). Operators on a non-develop worktree should run `/sync` to pull the updated develop. |

## Constraints

- Preflight guardrails are advisory — no `--force-promote` bypass flag.
- Concurrent invocations (second call while first `gh pr merge --rebase` is in flight) fail at PR-create or merge; both paths exit 1 with stderr and no state corruption.

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | Creates the epic branch and pins `claude.flowkit.prBase`. ship-epic is the symmetric closer. |
| `swarmkit:merge-stack` | Must run before ship-epic when the epic uses the stacked-PR model, to squash `worktree-agent-*` merge commits into linear history. |
| `flowkit:ship` (#894) | Will orchestrate `merge-stack → ship-epic → cut → release` when it ships. |
