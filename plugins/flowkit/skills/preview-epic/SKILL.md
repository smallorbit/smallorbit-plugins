---
name: preview-epic
description: Verify an epic-in-flight against the project's typecheck/test/lint commands before promoting it to the base branch. Auto-detects whether the epic uses the stacked-PR model (octopus-merge open PRs into a throwaway preview branch) or the direct-merge-to-epic model (run verify directly on the long-lived feature branch HEAD). Use to sanity-check an epic end-to-end before `swarmkit:merge-stack` (Model A) or before opening the final epic-to-base PR (Model B).
triggers:
  - "/preview-epic"
  - "preview the epic"
  - "preview stack"
  - "combine open PRs locally"
  - "validate epic before merge"
allowed-tools: Bash, Read, AskUserQuestion
---

# Preview Epic

Verify the integrated state of an epic against the project's verify commands before any merge to the base branch. The skill supports both epic-merge models that ship in this repo:

- **Model A — Stacked PRs.** Every PR in the epic stays OPEN, with each PR's `baseRefName` pointing at the previous PR's `headRefName`, ultimately rooting at the base branch. The integrated state must be synthesized locally via octopus merge (with sequential fallback). Finished by `swarmkit:merge-stack`.
- **Model B — Direct-merge-to-epic.** A long-lived `feature/<slug>-<issue>` branch is cut once (typically by `flowkit:cut-epic` or `squadkit:spawn-team --epic`). Each child PR targets that epic branch and squash-merges into it, then closes. The epic branch HEAD already IS the integrated state — there is nothing to synthesize. Finished by opening an epic-to-base PR.

The skill auto-detects which model applies and runs the right flow. The synthesized preview branch (Model A only) is local-only — nothing is pushed.

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

### 2. Resolve the epic branch and detect the model

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

Once an epic is resolved, classify the model:

```bash
OPEN_AGAINST_EPIC=$(gh pr list --state open --base "$EPIC_BRANCH" --limit 200 --json number --jq 'length')
MERGED_AGAINST_EPIC=$(gh pr list --state merged --base "$EPIC_BRANCH" --limit 200 --json number --jq 'length')

if [[ "$OPEN_AGAINST_EPIC" -gt 0 ]]; then
  MODEL="A"
elif git ls-remote --exit-code origin "$EPIC_BRANCH" >/dev/null 2>&1; then
  MODEL="B"
else
  MODEL="none"
fi
```

- **Model A** — open PRs target the epic branch. Synthesize the union via octopus merge (steps 3–6).
- **Model B** — zero open PRs but the epic branch exists (typically with squash-merged contributions accumulated). Run verify directly on the epic HEAD (step 6b).
- **Model none** — no open PRs and no remote epic branch. Stop and report: nothing to preview.

If Model A is selected but the PR-chain walk in step 3 cannot connect to `$BASE_BRANCH`, fall back to Model B (the open PRs are not actually a stack rooted at base) or report malformed epic.

### 3. (Model A) Discover the stack

List every open PR in the repo with the metadata needed to walk the base→head chain:

```bash
gh pr list --state open --limit 200 \
  --json number,headRefName,baseRefName,title,url
```

Build the stack:

1. Determine the entry PR.
   - If `$ARGUMENTS` is a number, use it as the entry PR.
   - Otherwise, resolve the PR for the current branch via `gh pr view --json number,headRefName,baseRefName`.
2. Walk **down** the chain (toward the root): from the entry PR, follow `baseRefName` → matching `headRefName` until the next base equals `$BASE_BRANCH`. That PR is the **stack root**.
3. Walk **up** the chain (toward the leaves): starting from the root, collect every PR whose `baseRefName` matches a previously-collected `headRefName`. Repeat until no more matches.

The result is an ordered list `[root, ..., leaf]` of PRs in the stack. If the entry PR has no chain to `$BASE_BRANCH`, the epic is malformed for Model A — fall back to Model B (treat the epic branch HEAD as the integrated state).

### 4. (Model A) Pick the preview branch name

```bash
ROOT_NUM=<root PR number>
ROOT_SLUG=<root PR headRefName, sanitized to [a-z0-9-]+>
PREVIEW_BRANCH="preview/${ROOT_NUM}-${ROOT_SLUG}"
```

If `$PREVIEW_BRANCH` already exists locally, append `-2`, `-3`, etc. until unused. Never overwrite an existing branch.

### 5. (Model A) Fetch and create the preview branch

```bash
git fetch origin
git checkout -b "$PREVIEW_BRANCH" "origin/$BASE_BRANCH"
```

Fetch every stack head ref so the merge has up-to-date refs:

```bash
gh pr list --state open --json number,headRefName --jq '.[].headRefName' | while read REF; do
  git fetch origin "$REF":"refs/remotes/origin/$REF" 2>/dev/null || true
done
```

### 6. (Model A) Try octopus merge first; sequential fallback on conflict

Octopus merge combines every head in a single commit. It only succeeds if all branches merge cleanly together.

```bash
HEADS=$(printf 'origin/%s ' "${STACK_HEADS[@]}")
if git merge --no-ff -m "preview: epic ${PREVIEW_BRANCH}" $HEADS; then
  STRATEGY="octopus"
else
  git merge --abort 2>/dev/null || true
  STRATEGY="sequential"
fi
```

If octopus failed, merge each head one at a time in stack order (root → leaf). Halt on the first conflict and report which PR introduced it.

```bash
for HEAD in "${STACK_HEADS[@]}"; do
  if ! git merge --no-ff -m "preview: merge ${HEAD}" "origin/$HEAD"; then
    CONFLICT_BRANCH="$HEAD"
    git merge --abort
    break
  fi
done
```

If a conflict halts the sequential merge, stop the skill and report:

- The preview branch name (so the user can inspect partial state if they re-run without `--abort`).
- The branch that conflicted.
- The PRs that merged cleanly before the conflict.

Do not proceed to verify commands when sequential merge fails.

### 6b. (Model B) Sync the epic branch locally

There is no synthesis to do — the epic branch already accumulates the squash-merged contributions. Pull it down and check it out so verify runs against the integrated state.

```bash
# Preserve any uncommitted state in the working tree.
STASHED=0
if ! git diff --quiet HEAD || ! git diff --cached --quiet; then
  git stash push -u -m "preview-epic auto-stash"
  STASHED=1
fi

git fetch origin "$EPIC_BRANCH":"refs/remotes/origin/$EPIC_BRANCH"

if git show-ref --verify --quiet "refs/heads/$EPIC_BRANCH"; then
  git checkout "$EPIC_BRANCH"
  git pull --ff-only origin "$EPIC_BRANCH" || {
    echo "Epic branch has diverged from origin; not auto-resolving. Aborting."
    [[ "$STASHED" -eq 1 ]] && git stash pop
    exit 1
  }
else
  git checkout -b "$EPIC_BRANCH" "origin/$EPIC_BRANCH"
fi
```

Record the merged-PR composition for the report:

```bash
MERGED_PRS=$(gh pr list --state merged --base "$EPIC_BRANCH" --limit 200 \
  --json number,title,headRefName --jq '.[] | "#\(.number) \(.title)"')
```

After verify completes, restore the user's pre-skill working state if any was stashed:

```bash
[[ "$STASHED" -eq 1 ]] && git stash pop
```

### 7. Resolve verify commands

Read `.squadkit/config.json` for `verify.typecheck`, `verify.test`, `verify.lint`, and `install`:

```bash
TYPECHECK=$(jq -r '.verify.typecheck // empty' .squadkit/config.json 2>/dev/null)
TEST=$(jq -r '.verify.test // empty' .squadkit/config.json 2>/dev/null)
LINT=$(jq -r '.verify.lint // empty' .squadkit/config.json 2>/dev/null)
INSTALL=$(jq -r '.install // empty' .squadkit/config.json 2>/dev/null)
```

For each command that resolved to empty, prompt the user via `AskUserQuestion`:

- "What command should I run for typecheck on this preview? (or skip)"
- "What command should I run for tests on this preview? (or skip)"
- "What command should I run for lint on this preview? (or skip)"

If the user declines any, skip that step. The skill does not hardcode `npm run test:run`, `npx tsc -b --noEmit`, or any other framework-specific command; the only source of commands is `.squadkit/config.json` or the user prompt.

### 8. Run verify commands

If `$INSTALL` is set and the working tree just changed (Model A always; Model B if HEAD moved), run install first. Then run typecheck, tests, and lint. Capture exit codes — do not abort the skill on failure; the user wants to see all results.

```bash
if [[ -n "$INSTALL" ]]; then
  echo "==> install: $INSTALL"
  eval "$INSTALL"
fi

if [[ -n "$TYPECHECK" ]]; then
  echo "==> typecheck: $TYPECHECK"
  eval "$TYPECHECK"
  TYPECHECK_RC=$?
fi

if [[ -n "$TEST" ]]; then
  echo "==> test: $TEST"
  eval "$TEST"
  TEST_RC=$?
fi

if [[ -n "$LINT" ]]; then
  echo "==> lint: $LINT"
  eval "$LINT"
  LINT_RC=$?
fi
```

### 9. Report

Print a concise summary tagged with the model:

**Model A:**

- Preview branch name.
- Merge strategy used (`octopus` or `sequential`), or the conflict report if sequential merge halted.
- Stack composition: every PR that was merged in, in order, as `#<num> <title>`.
- Verify outcomes: typecheck pass/fail/skipped, tests pass/fail/skipped, lint pass/fail/skipped.
- Suggested next step:
  - All green → `swarmkit:merge-stack` is safe.
  - Conflict or verify failure → fix the offending PR and re-run.

Suggested cleanup (Model A only):

```bash
git checkout "$BASE_BRANCH"
git branch -D "$PREVIEW_BRANCH"
```

**Model B:**

- Preview branch: `<epic-branch>` (Model B — direct-merge-to-epic; no synthesis needed).
- Stack composition: list of squash-merged PRs from `gh pr list --state merged --base <epic>`.
- Verify outcomes: typecheck pass/fail/skipped, tests pass/fail/skipped, lint pass/fail/skipped.
- Suggested next step:
  - All green → open the final epic-to-base PR: `gh pr create --base "$BASE_BRANCH" --head "$EPIC_BRANCH"`.
  - Verify failure → fix on the epic branch (or open a follow-up PR targeting the epic) and re-run.

No cleanup needed — the epic branch is long-lived.

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | Creates the long-lived `feature/<slug>-<issue>` branch and pins `claude.flowkit.prBase`. Both Model A and Model B preview against this branch. |
| `squadkit:spawn-team --epic` | Same as `cut-epic` plus spawns a crew that merges into the epic (Model B by default). |
| `swarmkit:merge-stack` | Run **after** `preview-epic` (Model A) confirms the combined tree is green. Cascades the actual merges. |
| `flowkit:ship` | Do not run while a Model A preview is checked out — switch back to the base branch first. |

## Constraints

- **Local-only.** Never push the synthesized preview branch (Model A); it is a throwaway integration check. The epic branch (Model B) is fetched but not modified beyond fast-forward.
- **Read defensively.** `.squadkit/config.json` may not exist — fall back to defaults and prompts.
- **No framework assumptions.** Verify commands come from `.squadkit/config.json` or user prompt; the skill never hardcodes `npm`, `pnpm`, `vitest`, `tsc`, `pytest`, `ruff`, `cargo`, or any other tool.
- **No PR retargeting.** This skill inspects PR metadata but never edits it. Use `swarmkit:merge-stack` for retargeting.
- **Halt cleanly on conflict (Model A).** Sequential merge must `git merge --abort` before reporting, so the working tree is left in a clean state on the preview branch's pre-conflict commit.
- **Preserve working state (Model B).** Auto-stash uncommitted changes before checking out the epic branch; restore on completion.
- **Idempotent in spirit.** Re-running with the same root will pick a fresh `preview/...-N` name (Model A) or simply re-fast-forward the epic branch (Model B) rather than clobbering existing local state.
- **Fail loud, not silent.** When no epic context can be resolved (no `--epic`, no `claude.flowkit.prBase` pin distinct from base, no `feature/*` checkout), report explicitly rather than no-op.
