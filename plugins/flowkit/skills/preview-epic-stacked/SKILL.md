---
name: preview-epic-stacked
description: Preview-epic sub-skill for the stacked-PR (Model A) flow — discover the open-PR stack, octopus-merge into a throwaway preview branch (with sequential fallback), and run verify against the synthesized integrated state. Invoked by `flowkit:preview-epic` after auto-detection; not meant to be called directly.
allowed-tools: Bash, Read, AskUserQuestion
---

# Preview Epic — Stacked PRs (Model A)

Sub-skill of `flowkit:preview-epic`. Synthesizes the integrated state of an epic whose contributions are still **open PRs** chained via `baseRefName` → previous PR's `headRefName`, ultimately rooting at `$BASE_BRANCH`. The integrated state is built locally via octopus merge (with sequential fallback) into a throwaway `preview/...` branch — nothing is pushed.

The dispatcher (`flowkit:preview-epic`) resolves `$BASE_BRANCH`, `$EPIC_BRANCH`, and `$ARGUMENTS` before invoking this sub-skill.

## Process

### 1. Discover the stack

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

The result is an ordered list `[root, ..., leaf]` of PRs in the stack. If the entry PR has no chain to `$BASE_BRANCH`, the epic is malformed for Model A — fall back to Model B by invoking `flowkit:preview-epic-direct` (treat the epic branch HEAD as the integrated state).

### 2. Pick the preview branch name

```bash
ROOT_NUM=<root PR number>
ROOT_SLUG=<root PR headRefName, sanitized to [a-z0-9-]+>
PREVIEW_BRANCH="preview/${ROOT_NUM}-${ROOT_SLUG}"
```

If `$PREVIEW_BRANCH` already exists locally, append `-2`, `-3`, etc. until unused. Never overwrite an existing branch.

### 3. Fetch and create the preview branch

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

### 4. Try octopus merge first; sequential fallback on conflict

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

### 5. Resolve verify commands

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

### 6. Run verify commands

If `$INSTALL` is set, run install first (the working tree just changed). Then run typecheck, tests, and lint. Capture exit codes — do not abort the skill on failure; the user wants to see all results.

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

### 7. Report

Print a concise summary tagged with the model:

- Preview branch name.
- Merge strategy used (`octopus` or `sequential`), or the conflict report if sequential merge halted.
- Stack composition: every PR that was merged in, in order, as `#<num> <title>`.
- Verify outcomes: typecheck pass/fail/skipped, tests pass/fail/skipped, lint pass/fail/skipped.
- Suggested next step:
  - All green → `swarmkit:merge-stack` is safe.
  - Conflict or verify failure → fix the offending PR and re-run.

Suggested cleanup:

```bash
git checkout "$BASE_BRANCH"
git branch -D "$PREVIEW_BRANCH"
```

## Constraints

- **Local-only.** Never push the synthesized preview branch; it is a throwaway integration check.
- **Halt cleanly on conflict.** Sequential merge must `git merge --abort` before reporting, so the working tree is left in a clean state on the preview branch's pre-conflict commit.
- **Idempotent in spirit.** Re-running with the same root will pick a fresh `preview/...-N` name rather than clobbering existing local state.
