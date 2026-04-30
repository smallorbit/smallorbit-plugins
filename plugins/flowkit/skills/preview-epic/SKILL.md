---
name: preview-epic
description: Verify an epic-in-flight against the project's typecheck/test/lint commands before promoting it to the base branch. Auto-detects whether the epic uses the stacked-PR model (octopus-merge open PRs into a throwaway preview branch) or the direct-merge-to-epic model (run verify directly on the long-lived feature branch HEAD). Use to sanity-check an epic end-to-end before `swarmkit:merge-stack` (Model A) or before opening the final epic-to-base PR (Model B).
triggers:
  - "/preview-epic"
  - "preview the epic"
  - "preview stack"
  - "combine open PRs locally"
  - "validate epic before merge"
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Preview Epic

Verify the integrated state of an epic against the project's verify commands before any merge to the base branch. The skill supports both epic-merge models that ship in this repo:

- **Model A — Stacked PRs.** Every PR in the epic stays OPEN, with each PR's `baseRefName` pointing at the previous PR's `headRefName`, ultimately rooting at the base branch. The integrated state must be synthesized locally via octopus merge (with sequential fallback). Finished by `swarmkit:merge-stack`. Per-model flow lives in `flowkit:preview-epic-stacked`.
- **Model B — Direct-merge-to-epic.** A long-lived `feature/<slug>-<issue>` branch is cut once (typically by `flowkit:cut-epic` or `squadkit:spawn-team --epic`). Each child PR targets that epic branch and squash-merges into it, then closes. The epic branch HEAD already IS the integrated state — there is nothing to synthesize. Finished by opening an epic-to-base PR. Per-model flow lives in `flowkit:preview-epic-direct`.

This top-level skill is a **dispatcher**: it resolves the base branch and the epic branch, classifies which model applies, and invokes the matching sub-skill via the Skill tool. The synthesized preview branch (Model A only) is local-only — nothing is pushed.

## Input

`$ARGUMENTS` — optional. Either:

1. `--epic <branch>` — explicit epic branch name. Overrides auto-detection of the epic.
2. A PR number anywhere in the stack — used as the entry point for Model A stack discovery.
3. Empty — the skill resolves the epic from `claude.flowkit.prBase` (canonical source) or the currently checked-out branch's PR.

## Process

### 1. Resolve the base branch

Look for `.squadkit/config.json` at the repo root. If present, read `baseBranch`:

```bash
BASE_BRANCH=$(jq -r '.baseBranch // empty' .squadkit/config.json 2>/dev/null)
```

If the file is absent or `baseBranch` is empty, default to `develop`. If `develop` does not exist on origin (`git ls-remote --exit-code origin develop`), prompt the user via `AskUserQuestion` for the base branch name before proceeding.

### 2. Resolve the epic branch

Resolve the epic branch in priority order:

1. `--epic <branch>` argument, if passed.
2. `git config --get claude.flowkit.prBase` — the canonical session-scoped pin set by `flowkit:cut-epic` and `squadkit:spawn-team --epic`. If this returns the base branch itself (e.g. `develop`), there is no epic in flight.
3. The currently checked-out branch, if it matches the squadkit feature pattern (`feature/*`).

```bash
EPIC_BRANCH=""
# 1. --epic arg wins
if [[ "$ARGUMENTS" == --epic* ]]; then
  EPIC_BRANCH=$(echo "$ARGUMENTS" | sed -E 's/^--epic[ =]+//')
fi
# 2. fall back to pinned config
if [[ -z "$EPIC_BRANCH" ]]; then
  PINNED=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
  if [[ -n "$PINNED" && "$PINNED" != "$BASE_BRANCH" ]]; then
    EPIC_BRANCH="$PINNED"
  fi
fi
# 3. fall back to current branch if it looks like a feature epic
if [[ -z "$EPIC_BRANCH" ]]; then
  CURRENT=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$CURRENT" == feature/* ]]; then
    EPIC_BRANCH="$CURRENT"
  fi
fi
```

If `$EPIC_BRANCH` is still empty, the user invoked the skill on a non-epic context (e.g. directly on `develop` with no pin). Stop with a clear message:

> No epic in flight. `claude.flowkit.prBase` is unset (or equals `$BASE_BRANCH`) and the current branch is not a `feature/*` epic. Run `/cut-epic` first, pass `--epic <branch>`, or check out the epic branch.

### 3. Classify the model and dispatch

```bash
OPEN_AGAINST_EPIC=$(gh pr list --state open --base "$EPIC_BRANCH" --limit 200 --json number --jq 'length')

if [[ "$OPEN_AGAINST_EPIC" -gt 0 ]]; then
  MODEL="A"
elif git ls-remote --exit-code origin "$EPIC_BRANCH" >/dev/null 2>&1; then
  MODEL="B"
else
  MODEL="none"
fi
```

- **Model A** — open PRs target the epic branch. Invoke `flowkit:preview-epic-stacked` to synthesize the union via octopus merge and run verify against the preview branch.
- **Model B** — zero open PRs but the epic branch exists (typically with squash-merged contributions accumulated). Invoke `flowkit:preview-epic-direct` to run verify directly on the epic HEAD.
- **Model none** — no open PRs and no remote epic branch. Stop and report: nothing to preview.

If Model A is selected but the sub-skill's PR-chain walk cannot connect to `$BASE_BRANCH`, the sub-skill will fall back by invoking `flowkit:preview-epic-direct` (the open PRs are not actually a stack rooted at base) or report malformed epic.

The dispatcher passes structured arguments to the chosen sub-skill via the Skill tool. The argument string is always `--base <BASE_BRANCH> --epic <EPIC_BRANCH>` followed by the original `$ARGUMENTS` (so any user-supplied flags like a PR number are preserved as trailing args). Example invocations:

```
# Model A
Skill("flowkit:preview-epic-stacked", "--base develop --epic feature/payments-42 123")

# Model B
Skill("flowkit:preview-epic-direct", "--base develop --epic feature/payments-42")
```

The `--base` and `--epic` flags are the mechanism by which the dispatcher hands off the resolved branch names; sub-skills must parse them from `$ARGUMENTS` at the top of their Process section.

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | Creates the long-lived `feature/<slug>-<issue>` branch and pins `claude.flowkit.prBase`. Both Model A and Model B preview against this branch. |
| `squadkit:spawn-team --epic` | Same as `cut-epic` plus spawns a crew that merges into the epic (Model B by default). |
| `swarmkit:merge-stack` | Run **after** `preview-epic` (Model A) confirms the combined tree is green. Cascades the actual merges. |
| `flowkit:ship` | Do not run while a Model A preview is checked out — switch back to the base branch first. |

| Sub-skill | Role |
|-----------|------|
| `flowkit:preview-epic-stacked` | Model A flow — stack discovery, octopus/sequential merge into a `preview/...` branch, verify, report. |
| `flowkit:preview-epic-direct` | Model B flow — fast-forward the epic branch locally, verify on HEAD, report. |

## Constraints

- **Read defensively.** `.squadkit/config.json` may not exist — fall back to defaults and prompts.
- **No framework assumptions.** Verify commands come from `.squadkit/config.json` or user prompt; the dispatcher and its sub-skills never hardcode `npm`, `pnpm`, `vitest`, `tsc`, `pytest`, `ruff`, `cargo`, or any other tool.
- **No PR retargeting.** This skill inspects PR metadata but never edits it. Use `swarmkit:merge-stack` for retargeting.
- **Fail loud, not silent.** When no epic context can be resolved (no `--epic`, no `claude.flowkit.prBase` pin distinct from base, no `feature/*` checkout), report explicitly rather than no-op.
