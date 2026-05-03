---
name: push-or-pr
description: Publish pending commits on the current branch by pushing directly when allowed, or by creating a feature branch and opening a PR when the target is branch-protected. Sub-skill used by /bump-versions, /flowkit:release, and /flowkit:hotfix.
---

# push-or-pr

Publish pending commits on the current branch to origin. The skill optimistically attempts a direct push; if origin rejects the push because the branch is protected, it saves HEAD, resets the local branch to its upstream, creates a feature branch carrying the saved commit(s), pushes that branch, and opens a PR. Skills that legitimately operate on `develop` (or any branch that may or may not be push-protected depending on repo policy) inline this snippet so they work uniformly across protected and unprotected setups.

The skill is push-only. Tag creation, post-merge sync, and merging the resulting PR remain caller responsibilities — they vary per caller (squash vs. merge strategy, post-sync requirements, tag placement).

## Caller contract

Before inlining the snippet, the caller sets these shell variables:

| Variable | Required when | Purpose |
|----------|---------------|---------|
| `PREFIX` | fallback engages | Branch-name prefix for the auto-created feature branch (e.g. `chore/bump-plugins`, `chore/sync-develop`). The skill appends `-YYYY-MM-DD` and a numeric suffix on collision. |
| `PR_TITLE` | fallback engages | Title for the PR opened against `$BASE`. |
| `PR_BODY` | fallback engages | Body for the PR. Caller assembles per [`plugins/_shared/pr-body.md`](../../../_shared/pr-body.md). |
| `BASE` | always | Base branch for the PR (typically `develop`). Defaults to `develop` if unset. |

After the snippet runs, the caller observes:

- `$PUSH_RESULT` — `direct` if the original push succeeded, `pr` if the fallback opened a PR, `noop` if there were no pending commits.
- `$NEW_BRANCH` — the auto-created feature branch name (set only when `$PUSH_RESULT=pr`).
- `$PR_URL` — the PR URL returned by `gh pr create` (set only when `$PUSH_RESULT=pr`).

The caller's working tree on success:

- `direct` — current branch unchanged, now in sync with origin.
- `pr` — current branch is the new feature branch (`$NEW_BRANCH`); the original protected branch is reset to its upstream so it no longer holds the unpublished commit. The commit lives on `$NEW_BRANCH` and in the open PR.
- `noop` — current branch unchanged.

## Process

### 1. Identify pending commits

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
UPSTREAM_REF="origin/$BRANCH"
if ! git rev-parse --verify --quiet "$UPSTREAM_REF" >/dev/null; then
  echo "ERROR: $UPSTREAM_REF does not exist locally — run \`git fetch origin\` before invoking push-or-pr." >&2
  exit 1
fi

PENDING=$(git rev-list --count "$UPSTREAM_REF..HEAD")
if [ "$PENDING" = "0" ]; then
  PUSH_RESULT=noop
fi
```

### 2. Attempt direct push

If there are pending commits, try the direct push first. Capture stderr so we can classify any failure:

```bash
if [ -z "${PUSH_RESULT:-}" ]; then
  PUSH_LOG=$(mktemp)
  if git push origin "HEAD:$BRANCH" >"$PUSH_LOG" 2>&1; then
    PUSH_RESULT=direct
    cat "$PUSH_LOG"
  else
    PUSH_OUTPUT=$(cat "$PUSH_LOG")
    echo "$PUSH_OUTPUT" >&2
  fi
  rm -f "$PUSH_LOG"
fi
```

### 3. Classify the rejection

If push failed, decide whether to engage the fallback or surface a real error. The rejection patterns below cover GitHub's branch-protection messages (`GH006`), repository rulesets (`push declined due to repository rule violations`), and the underlying refspec rejection (`remote rejected ... protected branch hook declined`):

```bash
if [ -z "${PUSH_RESULT:-}" ]; then
  if printf '%s' "$PUSH_OUTPUT" | grep -qiE "(protected branch|GH006|push declined due to repository rule|protected branch hook declined)"; then
    echo "note: direct push to $BRANCH rejected by branch protection — falling back to feature branch + PR." >&2
  else
    echo "ERROR: push to $BRANCH failed for a reason other than branch protection. See output above." >&2
    exit 1
  fi
fi
```

### 4. Engage the fallback

Save HEAD, switch to a new feature branch carrying the saved commits, then move the protected branch back to its upstream so the local copy doesn't drift. The order matters — `git branch -f` refuses to update the currently-checked-out branch, so checkout away first:

```bash
if [ -z "${PUSH_RESULT:-}" ]; then
  SAVED=$(git rev-parse HEAD)

  DATE=$(date +%Y-%m-%d)
  NEW_BRANCH="${PREFIX}-${DATE}"
  N=1
  while git ls-remote --exit-code origin "refs/heads/$NEW_BRANCH" >/dev/null 2>&1 \
     || git rev-parse --verify --quiet "refs/heads/$NEW_BRANCH" >/dev/null; do
    N=$((N + 1))
    NEW_BRANCH="${PREFIX}-${DATE}-${N}"
  done

  git checkout -b "$NEW_BRANCH" "$SAVED"
  git branch -f "$BRANCH" "$UPSTREAM_REF"
  git push -u origin "$NEW_BRANCH"
fi
```

### 5. Open the PR

```bash
if [ -z "${PUSH_RESULT:-}" ]; then
  PR_URL=$(gh pr create \
    --base "${BASE:-develop}" \
    --head "$NEW_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY")
  PUSH_RESULT=pr
fi
```

The skill does not merge the PR — the caller invokes `/flowkit:merge-pr` (or `gh pr merge ... --merge --delete-branch` for the merge-commit case) once it has self-reviewed.

### 6. Report

The skill emits a one-line summary on stdout so the caller's prose can show what happened:

```bash
case "$PUSH_RESULT" in
  direct) echo "push-or-pr: pushed $PENDING commit(s) directly to origin/$BRANCH." ;;
  pr)     echo "push-or-pr: opened $PR_URL ($BRANCH protected; commits live on $NEW_BRANCH)." ;;
  noop)   echo "push-or-pr: no pending commits — nothing to publish." ;;
esac
```

## Constraints

- Never force-push. The skill assumes the protected branch's upstream is the canonical state and resets the local copy to it before creating the feature branch.
- Never engage the fallback for non-protection-related push failures (auth, network, divergence). Surface those plainly.
- The skill leaves the working tree on the new feature branch when the fallback engages so the caller can immediately invoke `/flowkit:merge-pr` or self-review the PR.
- The skill does not push tags. Tag creation belongs to the caller and must run after the fallback PR (if any) is merged so tags point at the post-merge commit.
