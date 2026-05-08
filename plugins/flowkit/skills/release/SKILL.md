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
  SOURCE=$(git ls-remote --heads --sort=-version:refname origin "rc/*" \
    | head -1 \
    | awk '{print $2}' \
    | sed 's|refs/heads/||')
fi
```

If `SOURCE` is empty, abort with an error — there is nothing to release.

### 4. Aggregate issue references from merged PRs

Find the last release tag and collect all `Closes/Fixes/Resolves #N` references from PRs merged into `develop` since that tag's date. The tag-date filter ensures only PRs from the current release cycle are included, not all PRs ever merged:

```bash
LAST_TAG=$(git for-each-ref --sort=-creatordate \
  --format='%(refname:short)' \
  'refs/tags/v[0-9]*' | head -1)

if [ -n "$LAST_TAG" ]; then
  TAG_DATE=$(git log -1 --format=%aI "$LAST_TAG" \
    | python3 -c "import sys; from datetime import datetime, timezone; print(datetime.fromisoformat(sys.stdin.read().strip()).astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  MERGED_PRS=$(gh pr list --base develop --state merged --json body,mergedAt \
    | jq --arg td "$TAG_DATE" -r \
        '.[] | select((.mergedAt | fromdateiso8601) > ($td | fromdateiso8601)) | .body')
  ISSUE_REFS=$(printf '%s\n' "$MERGED_PRS" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | sort -u)
fi
```

Then find open epics whose children are all now closed and append their `Closes #N` refs. Epics may be wired to children via two mechanisms:

- **Legacy checklist** — epic body contains `- [ ] #N` / `- [x] #N` lines
- **Native sub-issues API** — children attached via GitHub's sub-issue relationship (used by `speckit:spec`)

Both paths must be checked, and the combined refs de-duplicated:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
EPIC_REFS_FILE=$(mktemp)

printf '%s\n' "$ISSUE_REFS" | grep -oE '[0-9]+' | sort -u | while read CHILD_N; do
  gh issue list --label "epic" --state open --json number,body \
      --jq ".[] | select(.body | test(\"- \\\\[[ x]\\\\] #${CHILD_N}\")) | .number" \
  | while read EPIC_N; do
    EPIC_BODY=$(gh issue view "$EPIC_N" --json body --jq '.body')
    OPEN_CHILDREN=$(printf '%s\n' "$EPIC_BODY" | grep -oE '- \[ \] #[0-9]+')
    [ -z "$OPEN_CHILDREN" ] && echo "Closes #$EPIC_N" >> "$EPIC_REFS_FILE"
  done
done

if [ -n "$ISSUE_REFS" ]; then
  SKIPPED_EPICS_FILE=$(mktemp)
  gh issue list --label "epic" --state open --json number --jq '.[].number' \
  | while read EPIC_N; do
    # Let gh invoke jq internally. Never round-trip JSON through a shell
    # variable: zsh's `echo` un-escapes backslash sequences by default, so
    # `echo "$SUB_ISSUES" | jq` turns escaped control chars (\n, \t, \")
    # inside string values into raw control bytes — invalid JSON. This is
    # the root cause behind prior recurrences (#328, #355, #482); a `tr`
    # filter cannot fix it because the hazardous bytes are 0x09 / 0x0a,
    # which are legitimate JSON whitespace between tokens.
    CHILDREN=$(gh api "repos/$REPO/issues/$EPIC_N/sub_issues" \
      --jq '.[] | "\(.number) \(.state)"' \
      2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "$EPIC_N" >> "$SKIPPED_EPICS_FILE"
      echo "Warning: failed to fetch or parse sub_issues for epic #$EPIC_N — skipping (will be listed in release report)" >&2
      continue
    fi

    [ -z "$CHILDREN" ] && continue

    ALL_RESOLVED=true
    printf '%s\n' "$CHILDREN" | while read CHILD_N CHILD_STATE; do
      [ -z "$CHILD_N" ] && continue
      ALREADY_CLOSED=$([ "$CHILD_STATE" = "closed" ] && echo true || echo false)
      IN_REFS=$(printf '%s\n' "$ISSUE_REFS" | grep -qiE "(closes|fixes|resolves) #${CHILD_N}\\b" && echo true || echo false)
      if [ "$ALREADY_CLOSED" = "false" ] && [ "$IN_REFS" = "false" ]; then
        ALL_RESOLVED=false
        break
      fi
    done

    [ "$ALL_RESOLVED" = "true" ] && echo "Closes #$EPIC_N" >> "$EPIC_REFS_FILE"
  done

  SKIPPED_EPICS=$(sort -u "$SKIPPED_EPICS_FILE" 2>/dev/null); rm -f "$SKIPPED_EPICS_FILE"
fi

EPIC_REFS=$(sort -u "$EPIC_REFS_FILE"); rm -f "$EPIC_REFS_FILE"
[ -n "$EPIC_REFS" ] && ISSUE_REFS="$ISSUE_REFS
$EPIC_REFS"
```

The sub-issues-API path only adds an epic when every child is either already closed or its number appears in this release's `ISSUE_REFS` (i.e. will close via this PR). Epics with any unresolved children outside the release cycle are not auto-closed. The final `sort -u` de-duplicates any epic detected by both paths.

If no tags exist yet, `ISSUE_REFS` remains empty and the PR body is unchanged.

### 5. Build release summary and create a PR from SOURCE → main

Compute the git log range between the source branch and main, then derive version bumps and synthesized release notes from that range.

```bash
RELEASE_DATE=$(date +%Y-%m-%d)

# --- version bumps ---
VERSION_BUMPS=$(git log origin/main..origin/"$SOURCE" --oneline \
  | grep -iE "bump|version|plugin\.json" \
  | sed 's/^[a-f0-9]* /- /' \
  || true)

# --- scope list ---
# Prefer .flowkit/scopes.txt at the repo root if the operator has pinned a
# canonical list (one scope per line; blank lines and `#` comments ignored).
# Otherwise auto-detect scopes from the release commit range: extract
# conventional-commit `type(scope):` tokens, normalize sub-scopes
# (`flowkit:open-pr` → `flowkit`), and dedupe. The skill adapts to whatever
# scopes the consumer repo actually uses — no hardcoded list.
SCOPES_FILE="$(git rev-parse --show-toplevel)/.flowkit/scopes.txt"
if [ -f "$SCOPES_FILE" ]; then
  PLUGINS=$(grep -v '^[[:space:]]*#' "$SCOPES_FILE" | grep -v '^[[:space:]]*$' || true)
else
  PLUGINS=$(git log origin/main..origin/"$SOURCE" --format=%s \
    | grep -oE '^[a-z]+\([^)]+\)' \
    | sed -E 's/^[a-z]+\(([^):/]+).*/\1/' \
    | sort -u \
    || true)
fi

# --- synthesized release notes ---
# Fetch merged-PR titles and the first sentence of each PR's ## Summary section
# since the last release tag. Group per scope using the list above. Render as
# human-readable bullets — one bullet per PR, phrased from the PR title with
# the Summary's first sentence appended if it adds context beyond the title.
RELEASE_NOTES_FILE=$(mktemp)
if [ -n "$LAST_TAG" ] && [ -n "$TAG_DATE" ]; then
  MERGED_PR_DATA=$(gh pr list --base develop --state merged --limit 200 \
    --json title,body,mergedAt \
    | jq --arg td "$TAG_DATE" -r \
        '.[] | select((.mergedAt | fromdateiso8601) > ($td | fromdateiso8601))
               | [.title,
                  (.body // "" | gsub("\r";"")
                    | capture("(?i)## Summary\n+(?<s>[^\n]+)").s // "")]
                 | @tsv')

  printf '%s\n' "$PLUGINS" | while read PLUGIN; do
    [ -z "$PLUGIN" ] && continue
    PLUGIN_NOTES=$(printf '%s\n' "$MERGED_PR_DATA" \
      | grep -iE '\('"$PLUGIN"'[:/)]' \
      | while IFS=$(printf '\t') read TITLE SUMMARY; do
          if [ -n "$SUMMARY" ] && [ "$SUMMARY" != "$TITLE" ]; then
            printf '- %s — %s\n' "$TITLE" "$SUMMARY"
          else
            printf '- %s\n' "$TITLE"
          fi
        done \
      || true)
    if [ -n "$PLUGIN_NOTES" ]; then
      printf '\n**%s**\n%s\n' "$PLUGIN" "$PLUGIN_NOTES" >> "$RELEASE_NOTES_FILE"
    fi
  done
fi
RELEASE_NOTES=$(cat "$RELEASE_NOTES_FILE"); rm -f "$RELEASE_NOTES_FILE"

# Smoke-test: verify the synthesis produced output before proceeding.
# Run this one-liner against the real repo to confirm jq parses the regex
# and at least one PR is matched:
#
#   TAG_DATE=$(git log -1 --format=%aI $(git for-each-ref --sort=-creatordate \
#     --format='%(refname:short)' 'refs/tags/v[0-9]*' | head -1) \
#     | python3 -c "import sys; from datetime import datetime, timezone; \
#       print(datetime.fromisoformat(sys.stdin.read().strip()) \
#             .astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))") \
#   && gh pr list --base develop --state merged --limit 200 --json title,body,mergedAt \
#   | jq --arg td "$TAG_DATE" -r \
#       '.[] | select((.mergedAt | fromdateiso8601) > ($td | fromdateiso8601))
#              | [.title, (.body // "" | gsub("\r";"")
#                 | capture("(?i)## Summary\n+(?<s>[^\n]+)").s // "")] | @tsv' \
#   | head -5
#
# A non-empty result (exit 0) confirms the pipeline is healthy.
# An empty result or non-zero exit means the tag range or jq regex needs investigation.

# --- narrative summary ---
# Synthesize a 1–3 sentence narrative from the collected merged-PR summaries
# and version bumps. State what this release contains overall — e.g.
# "Ship swarmkit stacked-merge bugfix alongside flowkit hotfix workflow tidy-up."
# Do not list individual file paths or repeat the title. Keep it to 3 sentences max.
NARRATIVE_SUMMARY="<!-- Write 1–3 sentences summarising what this release contains.
Derive the narrative from the version bumps and release notes computed above.
Example: "Ship swarmkit stacked-merge bugfix alongside flowkit hotfix workflow tidy-up." -->"

# --- assemble PR body ---
# <!-- include: plugins/_shared/pr-body.md -->
# The body shape below follows the canonical PR body spec defined in
# plugins/_shared/pr-body.md: Summary → Release summary → Version bumps →
# Release notes → issue-reference footer. Keep that order.
PR_BODY="## Summary

$NARRATIVE_SUMMARY

## Release summary

**Built from**: \`$SOURCE\`"

if [ -n "$VERSION_BUMPS" ]; then
  PR_BODY="$PR_BODY

### Version bumps
$VERSION_BUMPS"
fi

if [ -n "$RELEASE_NOTES" ]; then
  PR_BODY="$PR_BODY

### Release notes
$RELEASE_NOTES"
fi

[ -n "$ARGUMENTS" ] && PR_BODY="$PR_BODY

$ARGUMENTS"
[ -n "$ISSUE_REFS" ] && PR_BODY="$PR_BODY

$ISSUE_REFS"

# Lint: GitHub only parses one closing keyword per line. A footer like
# `Closes #1 #2 #3` silently leaves `#2` and `#3` open. Aggregation produces
# one token per line, but $ARGUMENTS or upstream PR bodies could smuggle the
# broken form into $PR_BODY — abort before opening the release PR.
if printf '%s\n' "$PR_BODY" | grep -qiE '(Closes|Fixes|Resolves) #[0-9]+[[:space:]]+#[0-9]+'; then
  echo "ERROR: Release PR body contains a space-separated closing-keyword footer (e.g. 'Closes #1 #2 #3')." >&2
  echo "GitHub only parses one closing keyword per line; the trailing refs would silently stay open." >&2
  echo "Rewrite the offending lines with one token per line (Closes #1 / Closes #2 / Closes #3) and re-run." >&2
  exit 1
fi

gh pr create \
  --base main \
  --head "$SOURCE" \
  --title "release: $RELEASE_DATE" \
  --body "$PR_BODY"
```

Capture the PR number from the URL output.

### 6. Merge the PR

`gh pr merge --merge --delete-branch` triggers an implicit local `git pull` after the merge. If the workspace is dirty that pull fails with `cannot pull with rebase: You have unstaged changes`. Wrap the call with the `flowkit:with-clean-workspace` script so any dirty state is auto-stashed and restored:

```bash
WITH_CLEAN_WORKSPACE_DIR="$(dirname "$SKILL_DIR")/with-clean-workspace"
bash "$WITH_CLEAN_WORKSPACE_DIR/scripts/with_clean_workspace.sh" -- \
  gh pr merge "$PR_URL" --merge --delete-branch || exit 1
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

### 9. Close referenced issues explicitly

When `main` is the GitHub default branch, the merged release PR's `Closes #N` footer auto-closed every aggregated issue. When the repo's default is `develop` (or any other non-`main` branch), the auto-close path silently no-ops and aggregated issues stay open. Run an explicit `gh issue close` loop over the same `$ISSUE_REFS` collected in step 4 so the lifecycle works on either default-branch configuration. The loop is idempotent — already-closed issues are skipped — so it's safe even when auto-close already fired.

```bash
ISSUE_NUMBERS=$(printf '%s\n' "$ISSUE_REFS" \
  | grep -oE '[0-9]+' \
  | sort -u)

CLOSED_ISSUES_FILE=$(mktemp)
printf '%s\n' "$ISSUE_NUMBERS" | while read N; do
  [ -z "$N" ] && continue
  STATE=$(gh issue view "$N" --json state --jq '.state' 2>/dev/null)
  if [ "$STATE" != "OPEN" ] && [ "$STATE" != "CLOSED" ]; then
    echo "note: could not determine state of #$N — attempting close anyway" >&2
  fi
  if [ "$STATE" != "CLOSED" ]; then
    if gh issue close "$N" --reason completed >/dev/null; then
      echo "$N" >> "$CLOSED_ISSUES_FILE"
    else
      echo "warning: failed to close issue #$N — close manually if needed" >&2
    fi
  fi
done
EXPLICITLY_CLOSED=$(sort -u "$CLOSED_ISSUES_FILE" 2>/dev/null); rm -f "$CLOSED_ISSUES_FILE"
```

`$EXPLICITLY_CLOSED` is the set of issues this loop closed (i.e. those that were still `OPEN` after the merge). On a `main`-default repo this list is typically empty because GitHub's auto-close already ran; on a `develop`-default repo it contains every aggregated issue. Surface it in the final report.

### 10. Clean up RC branches for today

The primary RC remote-branch cleanup happens in step 6 via `gh pr merge --delete-branch`, which removes the RC branch as part of the merge. This step is a safety net for RC branches that were ever created but never PR'd, or whose PR was closed without merging — in the happy path it should find nothing to delete. The leading `git fetch --prune` keeps local remote-tracking refs in sync with what step 6 already cleaned up so `git branch -a` stops listing the merged RC.

```bash
TODAY=$(date +%Y-%m-%d)
git fetch --prune origin
RC_BRANCHES=$(git ls-remote --heads origin "rc/$TODAY*" | awk '{print $2}' | sed 's|refs/heads/||')
if [ -z "$RC_BRANCHES" ]; then
  echo "No RC branches matching rc/$TODAY* on origin (already cleaned by --delete-branch)"
else
  echo "$RC_BRANCHES" | while read rc; do
    echo "Deleting orphan RC branch: $rc"
    git push origin --delete "$rc"
  done
fi
```

### 11. Back-merge main into develop

Bring develop's tip up to main so the next release cycle starts from parity. Use a real merge commit (not a fast-forward / squash) so the release merge from step 6 stays visible in develop's history.

```bash
git fetch origin
git checkout develop
git pull --ff-only origin develop
git merge --no-ff -m "chore(develop): back-merge release $TAG from main" origin/main
```

Publish the back-merge via the [`flowkit:push-or-pr`](../../push-or-pr/SKILL.md) sub-skill — direct pushes succeed when develop is unprotected and fall through to a merge-strategy back-merge PR when it isn't:

```bash
PUSH_OR_PR_DIR="$(dirname "$SKILL_DIR")/push-or-pr"
PR_BODY="## Summary

Back-merge release \`$TAG\` from main into develop.

## Test plan

- [ ] Confirm \`git log origin/main..origin/develop\` is empty after merge."

RESULT=$(bash "$PUSH_OR_PR_DIR/scripts/push_or_pr.sh" \
  --prefix "chore/sync-develop" \
  --title "chore(develop): back-merge release $TAG from main" \
  --body "$PR_BODY" \
  --base "develop")

PUSH_RESULT=$(printf '%s' "$RESULT" | jq -r '.push_result')
NEW_BRANCH=$(printf '%s' "$RESULT" | jq -r '.new_branch // empty')
PR_URL=$(printf '%s' "$RESULT" | jq -r '.pr_url // empty')
```

Branch on `$PUSH_RESULT`:

- `direct` — develop now matches main on origin. Done.
- `pr` — push-or-pr opened `$PR_URL` on `$NEW_BRANCH`. Merge it with `gh pr merge "$PR_URL" --merge --delete-branch` (use `--merge`, not `--squash`, to preserve the release merge commit's history). The local working tree is left on `$NEW_BRANCH` — switch back to develop and pull after the merge.
- `noop` — develop is already at or ahead of main on origin. Skip the publish and continue.

### 12. Report

Output:

- Tag created (e.g. `v2026.4.16`)
- PR number and URL
- Issues closed — list the aggregated `$ISSUE_REFS` numbers, and note which subset was closed by step 9's explicit loop (`$EXPLICITLY_CLOSED`) versus by GitHub's auto-close at merge time
- RC branches deleted
- Epics skipped due to sub_issues parse error, if any — read `$SKIPPED_EPICS` (set in step 4). When non-empty, list each epic number and remind the operator to check manually and add `Closes #N` to the release PR body if needed.

## Constraints

- Never push directly to `main` — always merge via PR
- Always create the git tag after the merge, never before
- Always sync both `main` and `develop` after release
- If no RC branch exists and staging is absent, abort with a clear error message
