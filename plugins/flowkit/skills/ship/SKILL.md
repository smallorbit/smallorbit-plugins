---
name: ship
description: Repo-level skill that orchestrates the full bubble-free release flow: merge-stack → ship-epic (when epic in flight) → cut → release. End-state: develop and main are linear, prBase is unset, RC branch deleted.
triggers:
  - "/ship"
  - "ship everything"
  - "merge stack and release"
  - "ship after swarm"
allowed-tools: Bash
---

# Ship

Orchestrate the full bubble-free release flow in one shot: detect any epic in flight, merge all open swarm PRs, promote the epic to develop (when applicable), cut a release candidate, and ship to main. End-state: `develop` and `main` are linear, `claude.flowkit.prBase` is unset, and the RC branch is deleted.

## Input

`$ARGUMENTS` — optional notes passed through to `/release` as release context. If omitted, everything is auto-derived.

## Process

### 1. Detect epic-in-flight

Resolve `$EPIC_BRANCH` from two signals:

```bash
EPIC_BRANCH=""

# Signal 1: pinned config (the canonical signal — set by cut-epic, swarm, spawn-team).
PINNED=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
if [[ -n "$PINNED" && "$PINNED" =~ ^feature/ ]]; then
  EPIC_BRANCH="$PINNED"
fi

# Signal 2: current HEAD is a feature/* branch (covers operators who checked out
# an epic without setting the pin).
if [[ -z "$EPIC_BRANCH" ]]; then
  CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ "$CURRENT" =~ ^feature/ ]]; then
    EPIC_BRANCH="$CURRENT"
  fi
fi
```

Signal 1 (pin) wins when both fire. If `$EPIC_BRANCH` is non-empty, this run promotes the epic before cutting. If empty, ship runs the develop-direct shape (merge-stack → cut → release, no ship-epic).

### 2. Merge open swarm PRs

Invoke `swarmkit:merge-stack` via the Skill tool:

```
Skill({skill: "swarmkit:merge-stack"})
```

merge-stack discovers and merges every open `worktree-agent-*` PR bottom-up. When `$EPIC_BRANCH` is set, the children target the epic branch — merge-stack handles that automatically.

If merge-stack reports "no open swarm PRs found", continue to the next step. If any merge fails with a conflict, stop immediately and report which PR is blocked. Do not proceed to step 3 until conflicts are resolved.

### 3. Promote the epic (conditional)

When `$EPIC_BRANCH` is empty, **skip this step**. Print a one-line note:

> No epic in flight — skipping ship-epic.

When `$EPIC_BRANCH` is non-empty, invoke `flowkit:ship-epic` via the Skill tool:

```
Skill({skill: "flowkit:ship-epic"})
```

ship-epic resolves the epic from `claude.flowkit.prBase`, opens the feature → develop PR with aggregated `Closes #N` tokens, rebase-merges, deletes the epic branch, and unsets `claude.flowkit.prBase`. Local `develop` is fast-forwarded.

If ship-epic fails (preflight failure, rebase-merge conflict, network), stop and surface its stderr. State is recoverable per ship-epic's own contract — pin and branch are intact. Do not proceed to step 4.

### 4. Cut a release candidate

Invoke `flowkit:cut` via the Skill tool:

```
Skill({skill: "flowkit:cut"})
```

cut creates `rc/<YYYY-MM-DD>.N` from `origin/develop`, pushes it, and pushes the matching tag.

If cut fails (e.g., empty diff against main), stop and report.

### 5. Release

Invoke `flowkit:release` via the Skill tool:

```
Skill({skill: "flowkit:release", arguments: $ARGUMENTS})
```

Pass `$ARGUMENTS` (this skill's input) through to release as its release-notes hint.

release runs the rebase-merge preflight, opens the RC → main PR, rebase-merges, tags, runs the explicit `gh issue close` loop, and cleans up RC branches.

If release fails, stop and report.

### 6. Final assertion and report

After all preceding steps complete:

```bash
PIN_AFTER=$(git config --get claude.flowkit.prBase 2>/dev/null || true)
if [[ -n "$PIN_AFTER" ]]; then
  echo "warning: claude.flowkit.prBase is still set to '$PIN_AFTER' after ship completed." >&2
  echo "  Expected empty when ship finishes from a clean state. Run \`git config --unset claude.flowkit.prBase\` to clear." >&2
fi
```

Report:

- Whether ship-epic ran (and the resulting epic PR number/URL if so)
- The RC branch created
- The release tag created on main
- Issues closed (aggregated from release's own report)
- The closing pin state (empty on the happy path; warning surfaced if not)

## Constraints

- If `merge-stack` encounters a conflict, stop — do not proceed with unresolved conflicts
- Never commit directly to `develop` or `main`
- No branch/commit/PR creation — those belong to `/pr` and `/swarm`
- If any step fails, stop immediately and report what failed and why
- ship-epic runs only when epic-in-flight is detected (Step 1's `$EPIC_BRANCH` non-empty). Otherwise it is silently skipped — calling ship-epic on a develop-direct run would produce a guaranteed error
- No internal verify gate. Operators run `/preview-epic` explicitly before invoking `/ship`. Symmetry with `ship-epic` and `cut-epic` themes
- Stop on any sub-skill failure. State is recoverable across partial failures: re-running `/ship` after the operator resolves the failure picks up where the chain left off
- No `--no-ship-epic` opt-out. Operators who need to skip ship-epic for an unusual reason invoke `/merge-stack && /cut && /release` directly
