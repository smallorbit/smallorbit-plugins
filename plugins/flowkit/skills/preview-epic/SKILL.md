---
name: preview-epic
description: Build a local preview branch that combines every open PR in an epic stack via octopus merge (with sequential fallback), then run the project's verify commands to validate the epic as a whole before any merge. Use to sanity-check a stacked-PR epic end-to-end before `swarmkit:merge-stack`.
triggers:
  - "/preview-epic"
  - "preview the epic"
  - "preview stack"
  - "combine open PRs locally"
  - "validate epic before merge"
allowed-tools: Bash, Read, AskUserQuestion
---

# Preview Epic

Combine every open PR in the current epic stack into a throwaway local preview branch, then run the project's typecheck and test commands against the combined tree. This catches integration breakage that single-PR CI cannot — each PR is green on its own base, but the union may not compile or pass tests.

The preview branch is local-only. Nothing is pushed. After inspecting the result, delete the preview branch and proceed with `swarmkit:merge-stack` (or address conflicts in the offending PR first).

## Input

`$ARGUMENTS` — optional. Either:

1. A PR number anywhere in the stack — used as the entry point for stack discovery.
2. Empty — the skill discovers the stack from the currently checked-out branch's PR.

## Process

### 1. Resolve the base branch

Look for `.squadkit/config.json` at the repo root. If present, read `baseBranch`:

```bash
BASE_BRANCH=$(jq -r '.baseBranch // empty' .squadkit/config.json 2>/dev/null)
```

If the file is absent or `baseBranch` is empty, default to `develop`. If `develop` does not exist on origin (`git ls-remote --exit-code origin develop`), prompt the user via `AskUserQuestion` for the base branch name before proceeding.

### 2. Discover the stack

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

The result is an ordered list `[root, ..., leaf]` of PRs in the stack. If the entry PR has no chain to `$BASE_BRANCH`, stop and report — the epic is malformed.

### 3. Pick the preview branch name

```bash
ROOT_NUM=<root PR number>
ROOT_SLUG=<root PR headRefName, sanitized to [a-z0-9-]+>
PREVIEW_BRANCH="preview/${ROOT_NUM}-${ROOT_SLUG}"
```

If `$PREVIEW_BRANCH` already exists locally, append `-2`, `-3`, etc. until unused. Never overwrite an existing branch.

### 4. Fetch and create the preview branch

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

### 5. Try octopus merge first

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

### 6. Sequential fallback

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

### 7. Resolve verify commands

Read `.squadkit/config.json` for `verify.typecheck` and `verify.test`:

```bash
TYPECHECK=$(jq -r '.verify.typecheck // empty' .squadkit/config.json 2>/dev/null)
TEST=$(jq -r '.verify.test // empty' .squadkit/config.json 2>/dev/null)
```

For each command that resolved to empty, prompt the user via `AskUserQuestion`:

- "What command should I run for typecheck on this preview? (or skip)"
- "What command should I run for tests on this preview? (or skip)"

If the user declines either, skip that step.

### 8. Run verify commands

Run typecheck first, then tests. Capture exit codes — do not abort the skill on failure; the user wants to see all results.

```bash
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
```

### 9. Report

Print a concise summary:

- Preview branch name.
- Merge strategy used (`octopus` or `sequential`), or the conflict report if sequential merge halted.
- Stack composition: every PR that was merged in, in order, as `#<num> <title>`.
- Verify outcomes: typecheck pass/fail/skipped, tests pass/fail/skipped.
- Suggested next step:
  - All green → `swarmkit:merge-stack` is safe.
  - Conflict or verify failure → fix the offending PR and re-run.

Suggested cleanup:

```bash
git checkout "$BASE_BRANCH"
git branch -D "$PREVIEW_BRANCH"
```

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | Creates the long-lived `feature/<slug>-<issue>` branch that this skill's stack roots into. |
| `swarmkit:merge-stack` | Run **after** `preview-epic` confirms the combined tree is green. Cascades the actual merges. |
| `flowkit:ship` | Do not run while a preview is checked out — switch back to the base branch first. |

## Constraints

- **Local-only.** Never push the preview branch; it is a throwaway integration check.
- **Read defensively.** `.squadkit/config.json` may not exist — fall back to defaults and prompts.
- **No framework assumptions.** Verify commands come from config or prompt; the skill never hardcodes `npm`, `pnpm`, `vitest`, `tsc`, `pytest`, or any other tool.
- **No PR retargeting.** This skill inspects PR metadata but never edits it. Use `swarmkit:merge-stack` for retargeting.
- **Halt cleanly on conflict.** Sequential merge must `git merge --abort` before reporting, so the working tree is left in a clean state on the preview branch's pre-conflict commit.
- **Idempotent in spirit.** Re-running with the same root will pick a fresh `preview/...-N` name rather than clobbering existing local state.
