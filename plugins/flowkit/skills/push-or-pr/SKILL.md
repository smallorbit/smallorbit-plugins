---
name: push-or-pr
description: Publish pending commits on the current branch by pushing directly when allowed, or by creating a feature branch and opening a PR when the target is branch-protected. Sub-skill used by /bump-versions, /flowkit:release, and /flowkit:hotfix.
---

# push-or-pr

Publish pending commits on the current branch to origin. Optimistically attempts a direct push; if origin rejects the push because the branch is protected, saves HEAD, resets the local branch to its upstream, creates a feature branch carrying the saved commit(s), pushes it, and opens a PR. Skills that legitimately operate on `develop` (or any branch that may or may not be push-protected depending on repo policy) call this sub-skill so they work uniformly across protected and unprotected setups.

The skill is push-only. Tag creation, post-merge sync, and merging the resulting PR remain caller responsibilities — those vary per caller (squash vs. merge strategy, post-sync requirements, tag placement).

## Invocation

The bash work lives in [`scripts/push_or_pr.sh`](./scripts/push_or_pr.sh). Callers invoke it directly:

```bash
RESULT=$(bash "$SKILL_DIR/scripts/push_or_pr.sh" \
  --prefix "$PREFIX" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --base "${BASE:-develop}")
```

`$SKILL_DIR` is the absolute path of the *push-or-pr* skill on disk. Callers resolve it as follows:

- **Sibling skills inside flowkit** (`release`, `hotfix`): `SKILL_DIR="$(dirname "$CALLER_SKILL_DIR")/push-or-pr"`, where `$CALLER_SKILL_DIR` is the caller's own `Base directory for this skill` value.
- **Repo-local skills** (e.g. `.claude/skills/bump-versions/`): hardcode `SKILL_DIR="plugins/flowkit/skills/push-or-pr"` relative to the repo root. The skill is project-local so it always knows where flowkit lives.

## Arguments

| Flag | Required | Default | Purpose |
|------|----------|---------|---------|
| `--prefix` | when fallback engages | — | Branch-name prefix for the auto-created feature branch (e.g. `chore/bump-plugins`, `chore/sync-develop`). The script appends `-YYYY-MM-DD` and a numeric suffix on collision. |
| `--title` | when fallback engages | — | Title for the fallback PR. |
| `--body` | when fallback engages | — | Body for the fallback PR. Caller assembles per [`plugins/_shared/pr-body.md`](../../../_shared/pr-body.md). Multi-line strings are fine — the caller quotes the value. |
| `--base` | always optional | `develop` | Base branch for the fallback PR. |

If the direct push succeeds, the fallback args are unused and may be omitted. If the push is rejected by branch protection but the fallback args are missing, the script exits non-zero with exit code 2.

## Output

On success the script emits a single bare JSON object on stdout (per [`plugins/_shared/script-authoring.md`](../../../_shared/script-authoring.md)):

| Key | Type | Present when | Meaning |
|-----|------|--------------|---------|
| `push_result` | string | always | `"direct"` \| `"pr"` \| `"noop"` |
| `branch` | string | always | The current branch at invocation time. |
| `pending_count` | integer | always | Commits ahead of upstream at invocation. |
| `new_branch` | string | `push_result == "pr"` | Auto-created feature branch carrying the saved commits. |
| `pr_url` | string | `push_result == "pr"` | URL of the PR opened against `--base`. |

On failure the script exits non-zero with stderr describing the failure and stdout empty.

## Caller follow-up

Branch on `push_result`:

- **`direct`** — commits are on origin's protected branch. Caller continues with whatever post-publish work it has (tag creation, sync, etc.).
- **`pr`** — PR is open at `pr_url`; commits live on `new_branch`; the local protected branch was reset to its upstream so it no longer holds the unpublished commit. Caller self-reviews and merges (`gh pr merge --squash --delete-branch` or `--merge --delete-branch` depending on whether history needs preserving), then switches back to the protected branch and pulls before continuing post-publish work.
- **`noop`** — no pending commits. Nothing was pushed; nothing to clean up.

When the fallback engages, the working tree is left on `new_branch`. Callers that need to return to the protected branch must explicitly `git checkout <branch> && git pull origin <branch>` after the PR merges.

## Branch-protection detection

The script classifies push failures as protection-related when stderr contains any of:

- `protected branch` (case-insensitive)
- `GH006` — GitHub's branch-protection error code
- `push declined due to repository rule violations` — repository rulesets
- `protected branch hook declined` — the underlying refspec rejection

Any other push failure (auth, network, divergence) exits non-zero with the captured stderr surfaced.

## Constraints

- Never force-push. The script assumes the protected branch's upstream is the canonical state and resets the local copy to it before creating the feature branch.
- Never engage the fallback for non-protection-related push failures.
- The script does not push tags. Tag creation belongs to the caller and must run after the fallback PR (if any) is merged so tags point at the post-merge commit.
- The script checks out `new_branch` before resetting the protected branch — `git branch -f` refuses to update the currently-checked-out branch, so the order matters.
