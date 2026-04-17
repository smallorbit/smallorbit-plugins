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

### 4. Create a PR from SOURCE → main

```bash
RELEASE_DATE=$(date +%Y-%m-%d)
PR_BODY="Release from $SOURCE"
[ -n "$ARGUMENTS" ] && PR_BODY="$PR_BODY

$ARGUMENTS"

gh pr create \
  --base main \
  --head "$SOURCE" \
  --title "release: $RELEASE_DATE" \
  --body "$PR_BODY"
```

Capture the PR number from the URL output.

### 5. Merge the PR

```bash
gh pr merge "$PR_URL" --squash --delete-branch
```

Use `--squash` for a clean, linear history regardless of whether the source is `staging` or an RC branch.

### 6. Sync main

Follow the `git-sync-main` sub-skill.

### 7. Create a git tag

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

### 8. Close referenced issues

Follow the `gh-close-referenced-issues` sub-skill, passing the release PR number.

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

### 10. Sync develop

Follow the `git-sync-develop` sub-skill.

### 11. Report

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
