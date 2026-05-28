---
name: push-or-pr
description: Publish pending commits on the current branch by creating a feature branch and opening a PR against --base — never push directly to the checked-out branch. Sub-skill used by /bump-versions.
---

# push-or-pr

Publish pending commits on the current branch to GitHub **only** via a pull request. The script never pushes to the branch you are on; it saves your commits on a dated feature branch, resets your local copy of that branch to match `origin/<branch>`, pushes the feature branch, and opens a PR. Skills that operate on `main` (or any shared line) call this sub-skill so publishing always goes through review.

The skill does not merge the PR, create tags, or run post-merge sync — those remain caller responsibilities.

## Invocation

The bash work lives in [`scripts/push_or_pr.sh`](./scripts/push_or_pr.sh). Callers invoke it directly:

```bash
RESULT=$(bash "$SKILL_DIR/scripts/push_or_pr.sh" \
  --prefix "$PREFIX" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --base "${BASE:-main}")
```

`$SKILL_DIR` is the absolute path of the *push-or-pr* skill on disk. Callers resolve it as follows:

- **Sibling skills inside flowkit** (`release`): `SKILL_DIR="$(dirname "$CALLER_SKILL_DIR")/push-or-pr"`, where `$CALLER_SKILL_DIR` is the caller's own `Base directory for this skill` value.
- **Repo-local skills** (e.g. `.claude/skills/bump-versions/`): hardcode `SKILL_DIR="plugins/flowkit/skills/push-or-pr"` relative to the repo root. The skill is project-local so it always knows where flowkit lives.

## Arguments

| Flag | Required | Default | Purpose |
|------|----------|---------|-------|
| `--prefix` | when there are pending commits | — | Branch-name prefix for the auto-created feature branch (e.g. `chore/bump-plugins`). The script appends `-YYYY-MM-DD` and a numeric suffix on collision. |
| `--title` | when there are pending commits | — | PR title. |
| `--body` | when there are pending commits | — | PR body. Caller assembles per [`plugins/_shared/pr-body.md`](../../../_shared/pr-body.md). Multi-line strings are fine — the caller quotes the value. |
| `--base` | always optional | `main` | Base branch for the PR. |

If there are no pending commits (`noop`), PR args are unused. If there are pending commits and any of `--prefix` / `--title` / `--body` is missing, the script exits non-zero with exit code 2.

## Output

On success the script emits a single bare JSON object on stdout (per [`plugins/_shared/script-authoring.md`](../../../_shared/script-authoring.md)):

| Key | Type | Present when | Meaning |
|-----|------|--------------|---------|
| `push_result` | string | always | `"pr"` \| `"noop"` |
| `branch` | string | always | The current branch at invocation time. |
| `pending_count` | integer | always | Commits ahead of upstream at invocation. |
| `new_branch` | string | `push_result == "pr"` | Feature branch carrying the saved commits. |
| `pr_url` | string | `push_result == "pr"` | URL of the PR opened against `--base`. |

On failure the script exits non-zero with stderr describing the failure and stdout empty.

## Caller follow-up

Branch on `push_result`:

- **`pr`** — PR is open at `pr_url`; commits live on `new_branch`; the local branch you published from was reset to its upstream so it no longer holds the unpublished commits. Merge (`gh pr merge --squash --delete-branch` or `--merge --delete-branch` per caller policy), then switch back to that branch and pull before continuing post-publish work.
- **`noop`** — no pending commits. Nothing was pushed; nothing to clean up.

After `pr`, the working tree is left on `new_branch`. Callers that need to return to the original branch must explicitly `git checkout <branch> && git pull origin <branch>` after the PR merges.

## Implementation note

The script checks out `new_branch` before resetting the original branch — `git branch -f` refuses to update the currently-checked-out branch, so the order matters.
