---
name: gh-label-merged-issues
description: Apply merged-to-develop label and comment to issues referenced in a merged PR. Sub-skill used by gh-merge and swarm.
---

# gh-label-merged-issues

Parse merged PR bodies for `Closes #N`, `Fixes #N`, or `Resolves #N` references and apply the `merged-to-develop` label to the referenced issues, skipping on-hold issues.

> **Note:** The label name `merged-to-develop` reflects the default `develop → main` branching model. If you target a different base branch (e.g. `main`), the label name will be semantically off but functionally harmless — it's only used for tracking, not for filtering issues out of the work queue.

**Important:** Skip any issue with the `on-hold` label — these should not be labeled regardless of PR references. Old/reverted PRs may still reference on-hold issues in their body text.

## Process

1. Accept a PR number as input (caller passes it).

2. Fetch the PR body:

```bash
BODY=$(gh pr view <PR_NUMBER> --json body --jq '.body')
```

3. Parse the body for `Closes/Fixes/Resolves #N` references (case-insensitive) and extract all issue numbers:

```bash
ISSUE_NUMBERS=$(echo "$BODY" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | grep -oE '[0-9]+' | sort -u)
```

4. If no references found, exit silently.

5. Ensure the `merged-to-develop` label exists in the repo:

```bash
gh label list | grep -q "merged-to-develop" || \
  gh label create "merged-to-develop" --description "Fix merged to develop, pending release" --color "0075CA"
```

6. For each referenced issue number:
   - Check labels: `gh issue view <N> --json labels --jq '.labels[].name'`
   - Skip if `on-hold` label present (print `⊘ Skipped #N (on-hold)`)
   - Otherwise:
     - Apply label: `gh issue edit <N> --add-label "merged-to-develop"`
     - Post comment: `gh issue comment <N> --body "Fix merged to develop in PR #<PR_NUMBER> — pending release."`
     - Print `✓ Labeled #N`

7. Report:
   - Issues labeled
   - Issues skipped (on-hold)
