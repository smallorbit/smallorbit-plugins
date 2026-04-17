---
name: release
description: Merge staging (or RC) to main via PR, tag the release, close referenced issues, and clean up RC branches.
triggers:
  - "/release"
  - "release this"
  - "ship to main"
  - "promote to main"
  - "release to production"
allowed-tools: Bash
---

# Release

Promote the current release candidate to production: open a PR into `main`, merge it, tag the commit, close referenced issues, delete RC branches, and sync develop.

## Input

`$ARGUMENTS` — optional version tag or release notes to include in the PR body. If omitted, everything is auto-derived.

## Process

### 1. Fetch latest remote state

```bash
git fetch origin
```

### 2. Runtime staging detection

```bash
git ls-remote --exit-code origin staging &>/dev/null && STAGING_EXISTS=true || STAGING_EXISTS=false
```

### 3. Determine source branch

```bash
if [ "$STAGING_EXISTS" = "true" ]; then
  SOURCE="staging"
else
  SOURCE=$(git ls-remote --sort=-version:refname origin "rc/*" \
    | head -1 \
    | awk '{print $2}' \
    | sed 's|refs/heads/||')
fi
```

If `SOURCE` is empty, abort with an error — there is nothing to release.

### 4. Aggregate issue references from merged PRs

Find the last release tag and collect all `Closes/Fixes/Resolves #N` references from PRs merged into `develop` since that tag's date. The tag-date filter ensures only PRs from the current release cycle are included, not all PRs ever merged:

```bash
LAST_TAG=$(git tag --sort=-version:refname | head -1)

if [ -n "$LAST_TAG" ]; then
  TAG_DATE=$(git log -1 --format=%aI "$LAST_TAG")
  MERGED_PRS=$(gh pr list --base develop --state merged --json body,mergedAt \
    --jq '.[] | select(.mergedAt > "'"$TAG_DATE"'") | .body')
  ISSUE_REFS=$(echo "$MERGED_PRS" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | sort -u)
fi
```

Then find open epics whose children are all now closed and append their `Closes #N` refs:

```bash
EPIC_REFS_FILE=$(mktemp)
echo "$ISSUE_REFS" | grep -oE '[0-9]+' | while read CHILD_N; do
  gh issue list --label "epic" --state open --json number,body \
    --jq ".[] | select(.body | test(\"- \\\\[[ x]\\\\] #${CHILD_N}\"))" \
  | grep -oE '"number":[0-9]+' | grep -oE '[0-9]+' | while read EPIC_N; do
    EPIC_BODY=$(gh issue view "$EPIC_N" --json body --jq '.body')
    OPEN_CHILDREN=$(echo "$EPIC_BODY" | grep -oE '- \[ \] #[0-9]+')
    [ -z "$OPEN_CHILDREN" ] && echo "Closes #$EPIC_N" >> "$EPIC_REFS_FILE"
  done
done
EPIC_REFS=$(sort -u "$EPIC_REFS_FILE"); rm -f "$EPIC_REFS_FILE"
[ -n "$EPIC_REFS" ] && ISSUE_REFS="$ISSUE_REFS
$EPIC_REFS"
```

If no tags exist yet, `ISSUE_REFS` remains empty and the PR body is unchanged.

### 5. Create a PR from SOURCE → main

```bash
RELEASE_DATE=$(date +%Y-%m-%d)
PR_BODY="Release from $SOURCE"
[ -n "$ARGUMENTS" ] && PR_BODY="$PR_BODY

$ARGUMENTS"
[ -n "$ISSUE_REFS" ] && PR_BODY="$PR_BODY

$ISSUE_REFS"

gh pr create \
  --base main \
  --head "$SOURCE" \
  --title "release: $RELEASE_DATE" \
  --body "$PR_BODY"
```

Capture the PR number from the URL output.

### 6. Merge the PR

```bash
gh pr merge "$PR_URL" --merge --delete-branch
```

Use `--merge` to preserve the full commit history from the RC branch in main.

### 7. Sync main

Follow the `git-sync-main` sub-skill.

### 8. Create a git tag

```bash
TAG="v$(date +%Y.%-m.%-d)"
```

If the tag already exists, append an increment:

```bash
N=1
while git ls-remote --exit-code origin "refs/tags/$TAG.$N" &>/dev/null; do
  N=$((N + 1))
done
[ "$(git ls-remote --exit-code origin refs/tags/$TAG &>/dev/null; echo $?)" = "0" ] \
  && TAG="$TAG.$N"

git tag "$TAG"
git push origin "$TAG"
```

### 9. Clean up RC branches for today

```bash
TODAY=$(date +%Y-%m-%d)
git ls-remote origin "rc/$TODAY*" \
  | awk '{print $2}' \
  | sed 's|refs/heads/||' \
  | while read rc; do
      git push origin --delete "$rc" 2>/dev/null || true
    done
```

### 11. Sync develop

Follow the `git-sync-develop` sub-skill. Because the release PR was merged with a merge commit (not squashed), `git merge origin/main` on develop will correctly resolve without divergence — no force-push is needed.

### 12. Report

Output:
- Tag created (e.g. `v2026.4.16`)
- PR number and URL
- Issues closed
- RC branches deleted

## Constraints

- Never push directly to `main` — always merge via PR
- Always create the git tag after the merge, never before
- Always sync both `main` and `develop` after release
- If no RC branch exists and staging is absent, abort with a clear error message
