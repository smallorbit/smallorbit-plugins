---
name: restack
description: Rebase the open descendant PRs of a parent PR onto its updated head and force-push, recursing through transitive descendants. Use mid-review when a parent PR receives new commits and the stack needs to stay current. Powers swarmkit:merge-stack step 5e.
triggers:
  - "/restack"
  - "rebase descendants"
  - "restack the stack"
  - "rebase children of PR"
allowed-tools: Bash
---

# restack

Rebase the open descendant PRs of a parent PR onto its updated head and force-push, recursing through transitive descendants. Use mid-review after revising a stacked PR to keep the stack consistent for reviewers.

## Input

`$ARGUMENTS` — required. One of:

- `--pr <N>` — PR whose descendant subtree is rebased onto its head. Recursive.
- Empty — auto-resolve the PR for the current branch (`gh pr list --head $BRANCH`); equivalent to passing the resolved PR as `--pr`.

The `--branch <head> --upstream <ref>` form is a cross-plugin entry point used by `swarmkit:merge-stack` step 5e. Operators don't pass it directly; documented here for completeness.

## Process

1. Capture the skill directory from the harness header line:

   `Base directory for this skill: <absolute path>`

   ```bash
   export SKILL_DIR="<absolute path from the header line>"
   ```

2. Run the script:

   ```bash
   RESULT=$(bash "$SKILL_DIR/scripts/restack.sh" $ARGUMENTS)
   ```

3. On success (`RESULT` is non-empty JSON), report a summary:

   > Restacked subtree of PR #N. Succeeded: K branches. Failed: M branches (subtrees skipped). See log above for details.

   where `N` is `.parent.pr_number`, `K` is `(.succeeded | length)`, and `M` is `(.failed | length)` from `RESULT`.

   For single-branch mode (no `.parent`), report:

   > Rebased branch onto upstream. Succeeded: K. Failed: M.

4. On failure (non-zero exit, empty stdout), surface stderr and stop.

## Script contract

`scripts/restack.sh` implements dirty-workspace stashing, BFS descendant discovery, and a `git rebase` + `git push --force-with-lease` loop. On success it prints **bare JSON** on stdout:

| Field | Type | Meaning |
|-------|------|---------|
| `mode` | string | `"recursive"` or `"single-branch"`. |
| `parent` | object \| null | `{pr_number, head_branch}` for recursive mode; `null` for single-branch. |
| `succeeded` | array | `[{branch, upstream, force_pushed: true}, ...]`. |
| `failed` | array | `[{branch, upstream, reason: "rebase-conflict" \| "force-push-rejected" \| "branch-not-found"}, ...]`. |
| `skipped` | array | `[{branch, reason: "ancestor-failed", ancestor: "<branch>"}, ...]`. |
| `original_head` | string | The git ref the operator was on at invocation, restored before exit. |

Exit codes: `0` success (including no descendants). `1` runtime failure. `2` invalid argument.
