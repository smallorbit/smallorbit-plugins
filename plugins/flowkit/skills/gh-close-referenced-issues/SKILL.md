---
name: gh-close-referenced-issues
description: Close issues referenced in a merged PR body and auto-close completed epics. Sub-skill used by release.
---

# gh-close-referenced-issues

Parse a merged PR body for `Closes/Fixes/Resolves #N` references and close each referenced issue when its work ships to `main`. Distinct from `gh-label-merged-issues`, which only labels issues on merge to `develop`.

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

5. For each referenced issue number:
   - Check labels: `gh issue view <N> --json labels --jq '.labels[].name'`
   - Skip if `on-hold` label present (print `⊘ Skipped #N (on-hold)`)
   - Otherwise close the issue with a comment:
     ```bash
     gh issue close <N> --comment "Shipped in this release."
     ```
   - Print `✓ Closed #N`

6. After closing, check for epic completion. For each closed issue `<N>`:
   - Find open issues with the `epic` label whose body contains a checklist reference to `#<N>` (matches both `- [ ] #N` and `- [x] #N`):
     ```bash
     gh issue list --label "epic" --state open --json number,body \
       --jq '.[] | select(.body | test("- \\[[ x]\\] #<N>"))'
     ```
   - For each matching epic, check whether all checklist items are now closed:
     ```bash
     EPIC_BODY=$(gh issue view <EPIC_N> --json body --jq '.body')
     CHILD_NUMBERS=$(echo "$EPIC_BODY" | grep -oE '- \[[ x]\] #[0-9]+' | grep -oE '#[0-9]+' | tr -d '#')
     ```
   - For each child number, verify its state: `gh issue view <CHILD_N> --json state --jq '.state'`
   - If all children are `CLOSED`, close the epic:
     ```bash
     gh issue close <EPIC_N> --comment "All child issues resolved. Epic complete."
     ```
   - Print `✓ Closed epic #<EPIC_N>`

7. Report summary:
   - Issues closed
   - Epics closed
   - Issues skipped (on-hold)
