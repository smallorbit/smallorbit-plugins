---
name: preview-epic-direct
description: Preview-epic sub-skill for the direct-merge-to-epic (Model B) flow — fast-forward the long-lived feature branch locally and run verify directly against its HEAD (no synthesis needed). Invoked by `flowkit:preview-epic` after auto-detection; not meant to be called directly.
allowed-tools: Bash, Read, AskUserQuestion
---

# Preview Epic — Direct Merge to Epic (Model B)

Sub-skill of `flowkit:preview-epic`. The long-lived `feature/<slug>-<issue>` epic branch already accumulates the squash-merged contributions — there is nothing to synthesize. This sub-skill fetches the epic branch, fast-forwards locally, and runs verify directly on its HEAD.

The dispatcher (`flowkit:preview-epic`) resolves `$BASE_BRANCH` and `$EPIC_BRANCH` before invoking this sub-skill, encoding them as structured flags in the argument string passed via the Skill tool.

## Process

### 1. Parse dispatcher arguments

Extract `--base` and `--epic` from `$ARGUMENTS`.

```bash
BASE_BRANCH=""
EPIC_BRANCH=""
_ARGS="$ARGUMENTS"

while [[ -n "$_ARGS" ]]; do
  case "$_ARGS" in
    --base\ *)
      _ARGS="${_ARGS#--base }"
      BASE_BRANCH="${_ARGS%% *}"
      _ARGS="${_ARGS#$BASE_BRANCH}"
      _ARGS="${_ARGS# }"
      ;;
    --epic\ *)
      _ARGS="${_ARGS#--epic }"
      EPIC_BRANCH="${_ARGS%% *}"
      _ARGS="${_ARGS#$EPIC_BRANCH}"
      _ARGS="${_ARGS# }"
      ;;
    *)
      _ARGS=""
      ;;
  esac
done
```

If either `$BASE_BRANCH` or `$EPIC_BRANCH` is empty after parsing, stop with:

> Missing required arguments. This sub-skill must be invoked by `flowkit:preview-epic` with `--base <branch> --epic <branch>`.

### 2. Sync the epic branch locally

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

### 3. Resolve verify commands

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

### 4. Run verify commands

If `$INSTALL` is set and HEAD moved during the fetch/fast-forward, run install first. Then run typecheck, tests, and lint. Capture exit codes — do not abort the skill on failure; the user wants to see all results.

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

### 5. Report

Print a concise summary tagged with the model:

- Preview branch: `<epic-branch>` (Model B — direct-merge-to-epic; no synthesis needed).
- Stack composition: list of squash-merged PRs from `gh pr list --state merged --base <epic>`.
- Verify outcomes: typecheck pass/fail/skipped, tests pass/fail/skipped, lint pass/fail/skipped.
- Suggested next step:
  - All green → open the final epic-to-base PR: `gh pr create --base "$BASE_BRANCH" --head "$EPIC_BRANCH"`.
  - Verify failure → fix on the epic branch (or open a follow-up PR targeting the epic) and re-run.

No cleanup needed — the epic branch is long-lived.

## Constraints

- **Epic branch is fetched, not modified beyond fast-forward.** Diverged remotes abort rather than auto-resolving.
- **Preserve working state.** Auto-stash uncommitted changes before checking out the epic branch; restore on completion.
- **Idempotent in spirit.** Re-running simply re-fast-forwards the epic branch rather than clobbering existing local state.
