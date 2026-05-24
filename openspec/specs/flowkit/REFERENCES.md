# flowkit — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `plugins/flowkit/` unless otherwise noted.
Line numbers verified on 2026-05-23.

---

## Requirement: Base Branch Resolution

**Sources**
- `../_shared/base-resolution.md:5-12` — the four-step canonical algorithm.
- `skills/open-pr/SKILL.md:49-85` — bash implementation of the chain including the self-targeting guard.

### Scenario: Explicit --base flag wins
**Source:** `skills/open-pr/SKILL.md:51-54` — grep for `--base[= ]` token in `$ARGUMENTS`; assignment of `BASE`.
**Interpolated; no direct test.**

### Scenario: Config key consulted after explicit arg
**Source:** `skills/open-pr/SKILL.md:57-59` — `BASE=$(git config claude.flowkit.prBase 2>/dev/null)`.
**Interpolated; no direct test.**

### Scenario: develop preferred when on origin
**Source:** `skills/open-pr/SKILL.md:62-66` — `git ls-remote --heads origin develop | grep -q 'refs/heads/develop'` then `BASE="develop"`.
**Interpolated; no direct test.**

### Scenario: Repo default fallback with warning
**Source:** `skills/open-pr/SKILL.md:69-73` — `gh repo view ... defaultBranchRef` resolution plus the `warning: no base branch configured...` stderr emission.
**Interpolated; no direct test.**

### Scenario: Self-targeting guard rejects pin pointing at current branch
**Source:** `skills/open-pr/SKILL.md:76-84` — `if [ "$BASE" = "$HEAD_BRANCH" ]; then ... exit 1; fi` with multi-line operator guidance.
**Interpolated; no direct test.**

---

## Requirement: Default Branch Prompt

**Sources**
- `skills/default-branch-prompt/SKILL.md:1-101` — full sub-skill including marker check, gh probe, three-option prompt, double-confirm path.
- `skills/open-pr/SKILL.md:23-31` — call-site explaining the no-op cases and that open-pr is fire-and-forget over the result.

### Scenario: Marker skips the prompt
**Source:** `skills/default-branch-prompt/SKILL.md:13-18` — `if [ "$(git config --get claude.flowkit.defaultBranchPrompted ...)" = "true" ]; then exit 0; fi`.
**Interpolated; no direct test.**

### Scenario: Non-main default skips the prompt
**Source:** `skills/default-branch-prompt/SKILL.md:22-42` — `gh repo view --json defaultBranchRef` then `if [ "$DEFAULT_BRANCH" != "main" ]; then exit 0; fi`. Comment on line 28 covers `gh` failure paths.
**Interpolated; no direct test.**

### Scenario: Switch requires double confirmation
**Source:** `skills/default-branch-prompt/SKILL.md:60-69` — second AskUserQuestion wording and options.
**Interpolated; no direct test.**

### Scenario: Successful switch sets the marker
**Source:** `skills/default-branch-prompt/SKILL.md:71-77` — `gh repo edit --default-branch develop` followed by setting the marker on success.
**Interpolated; no direct test.**

### Scenario: Cancelled switch keeps marker unset
**Source:** `skills/default-branch-prompt/SKILL.md:79` — "On `Cancel`: marker stays unset; the three-option prompt resurfaces next time."
**Interpolated; no direct test.**

### Scenario: Keep or skip sets the marker without mutation
**Source:** `skills/default-branch-prompt/SKILL.md:81-95` — both `Keep main as default` and `Don't ask again` branches set `git config claude.flowkit.defaultBranchPrompted true` and do not mutate the repo.
**Interpolated; no direct test.**

---

## Requirement: Branch Creation

**Sources**
- `skills/create-branch/SKILL.md:1-65` — full skill: fetch, name derivation, validation, checkout from `origin/develop`.

### Scenario: Inferred name from description
**Source:** `skills/create-branch/SKILL.md:32-36` — type-prefix selection, kebab-case conversion, 50-char cap with examples.
**Interpolated; no direct test.**

### Scenario: Explicit branch name used as-is
**Source:** `skills/create-branch/SKILL.md:31` — "If it looks like a branch name (kebab-case, already has a prefix), use it directly."
**Interpolated; no direct test.**

### Scenario: Reserved names rejected
**Source:** `skills/create-branch/SKILL.md:42-47` — list of rejected names and the stop-and-ask directive.
**Interpolated; no direct test.**

### Scenario: Branch always cut from origin
**Source:** `skills/create-branch/SKILL.md:51-53` — `git checkout -b <name> origin/develop`. Also constraint at line 63: "Always branch from `origin/develop`, never from a local `develop`".
**Interpolated; no direct test.**

---

## Requirement: Conventional Commit Format

**Sources**
- `skills/commit/SKILL.md:1-116` — full commit skill including type enum, subject-length rule, body guidance, HEREDOC requirement.

### Scenario: Subject under 72 characters
**Source:** `skills/commit/SKILL.md:39-41` — "Keep the subject line (first line) under 72 characters."
**Interpolated; no direct test.**

### Scenario: Logical groupings split into multiple commits
**Source:** `skills/commit/SKILL.md:62-64` — "Group files by concern — each group should represent a single logical change ... If multiple concerns are present, plan one commit per concern."
**Interpolated; no direct test.**

### Scenario: Nothing to commit reported cleanly
**Source:** `skills/commit/SKILL.md:115` — "If `git status` is clean, report 'Nothing to commit' and stop".
**Interpolated; no direct test.**

### Scenario: HEREDOC syntax used for multi-line messages
**Source:** `skills/commit/SKILL.md:86-95` — full HEREDOC commit template. Also constraint at line 112.
**Interpolated; no direct test.**

### Scenario: Amend never used
**Source:** `skills/commit/SKILL.md:114` — "Never amend an existing commit — always create new ones".
**Interpolated; no direct test.**

---

## Requirement: PR Body Standard

**Sources**
- `../_shared/pr-body.md` — canonical body shape (Summary / Changes / Test plan) plus issue-reference footer grammar.
- `skills/open-pr/SKILL.md:112-127` — body assembly with the canonical three sections.
- `skills/open-pr/SKILL.md:144-160` — lint that rejects broken multi-ref footers.
- `skills/open-pr/SKILL.md:100-110` — issue-ref token discovery from commits with case-insensitive match and verbatim emission.

### Scenario: Three sections in order
**Source:** `skills/open-pr/SKILL.md:115-119` — explicit list of `## Summary`, `## Changes`, `## Test plan`, then footer.
**Interpolated; no direct test.**

### Scenario: Closing-keyword tokens one per line
**Source:** `../_shared/pr-body.md` (Issue-reference footer section) — "Always emit one token per line (`Closes #A` / `Closes #B`)."
**Interpolated; no direct test.**

### Scenario: Broken multi-ref footer rejected
**Source:** `skills/open-pr/SKILL.md:148-158` — grep for space-separated multi-ref form; `exit 1` with rewrite guidance. "Fail loudly rather than auto-rewriting".
**Interpolated; no direct test.**

### Scenario: Verbatim forwarding of author-committed keywords
**Source:** `skills/open-pr/SKILL.md:100-110` — "case-insensitively ... but emit each match verbatim (preserving the author's original casing)". Also override rule at line 127.
**Interpolated; no direct test.**

---

## Requirement: Open PR

**Sources**
- `skills/open-pr/SKILL.md:1-185` — full skill.

### Scenario: Protected branch blocked
**Source:** `skills/open-pr/SKILL.md:33-41` — "If the current branch is `develop`, `main`, or `master`, stop immediately". Also constraint at line 182.
**Interpolated; no direct test.**

### Scenario: Default-branch prompt fires before any other preflight
**Source:** `skills/open-pr/SKILL.md:23-31` — "Before any other preflight, invoke the default-branch-prompt sub-skill."
**Interpolated; no direct test.**

### Scenario: Branch pushed with -u, not force-pushed
**Source:** `skills/open-pr/SKILL.md:87-91` — `git push -u origin HEAD`. Also constraint at line 184.
**Interpolated; no direct test.**

### Scenario: Closing-keyword on non-default-branch base warned
**Source:** `skills/open-pr/SKILL.md:129-140` — step 7 grep + `gh repo view defaultBranchRef` comparison; `note: 'Closes #N' won't fire ...` to stderr. "This is informational only — do not abort or rewrite the body."
**Interpolated; no direct test.**

---

## Requirement: PR Lifecycle Orchestrator

**Sources**
- `skills/pr/SKILL.md:1-54` — full chain orchestrator.

### Scenario: Branch creation skipped on feature branch
**Source:** `skills/pr/SKILL.md:22-32` — branch-detection `git rev-parse --abbrev-ref HEAD`, then "If the current branch is already a non-protected branch ... skip step 2".
**Interpolated; no direct test.**

### Scenario: Commit skipped on clean workspace
**Source:** `skills/pr/SKILL.md:34-38` — "If the workspace is already clean (nothing to commit), skip this step."
**Interpolated; no direct test.**

### Scenario: Failure aborts the chain
**Source:** `skills/pr/SKILL.md:52` — "If any step fails, stop and report the error — do not continue to the next step".
**Interpolated; no direct test.**

---

## Requirement: PR Merge

**Sources**
- `skills/merge-pr/SKILL.md:1-63` — skill prose.
- `skills/merge-pr/SKILL.md:46-56` — Script contract describing worktree cleanup, stacked-PR retargeting, `with-clean-workspace` wrapper.

### Scenario: Rebase-merge only
**Source:** `skills/merge-pr/SKILL.md:46-48` — "with-clean-workspace–wrapped `gh pr merge --rebase --delete-branch`". Also constraint at line 61: "Always rebase-merge (never squash or merge commit)".
**Interpolated; no direct test.**

### Scenario: Stacked children retargeted before merge
**Source:** `skills/merge-pr/SKILL.md:14` — "Open PRs that use this PR's head as their base are retargeted first so GitHub does not auto-close them when the head branch is deleted." Script contract line 46-48 confirms.
**Interpolated; no direct test.**

### Scenario: Main worktree holding head auto-checks out base
**Source:** `skills/merge-pr/SKILL.md:48` — "When the branch is held by the main worktree (the canonical state after `push-or-pr`) the script instead runs `git checkout <base>` in the main worktree".
**Interpolated; no direct test.**

### Scenario: Caller-owned worktree refuses removal
**Source:** `skills/merge-pr/SKILL.md:48` — "unless the caller's cwd is inside that worktree, in which case the script refuses with operator guidance to exit the worktree first".
**Interpolated; no direct test.**

### Scenario: Implicit post-merge pull wrapped against dirty workspace
**Source:** `skills/merge-pr/SKILL.md:46-48` — "`with-clean-workspace`–wrapped `gh pr merge`". Underlying mechanism in `skills/with-clean-workspace/SKILL.md`.
**Interpolated; no direct test.**

### Scenario: Issues never closed by merge-pr
**Source:** `README.md:226-228` — "Issue Lifecycle: `/merge-pr` never closes issues — that's intentional. Issues are closed by `/release` when work actually ships to `main`."
**Interpolated; no direct test.**

---

## Requirement: Restack Descendants

**Sources**
- `skills/restack/SKILL.md:1-66` — full skill including script contract and result schema.

### Scenario: Auto-resolve parent from current branch
**Source:** `skills/restack/SKILL.md:21-22` — "Empty — auto-resolve the PR for the current branch (`gh pr list --head $BRANCH`); equivalent to passing the resolved PR as `--pr`".
**Interpolated; no direct test.**

### Scenario: Subtree walked breadth-first
**Source:** `skills/restack/SKILL.md:55` — "`scripts/restack.sh` implements ... BFS descendant discovery". Sibling-continuation behavior implied by `skipped` array shape at line 63.
**Interpolated; no direct test.**

### Scenario: Rebase conflict on one branch does not stop siblings
**Source:** `skills/restack/SKILL.md:62-63` — `failed` array with `reason: "rebase-conflict"` plus `skipped` array with `reason: "ancestor-failed"` indicates sibling continuation.
**Interpolated; no direct test.**

### Scenario: Force-push uses lease
**Source:** `skills/restack/SKILL.md:55` — "a `git rebase` + `git push --force-with-lease` loop".
**Interpolated; no direct test.**

---

## Requirement: Shared-Branch Publishing

**Sources**
- `skills/push-or-pr/SKILL.md:1-68` — full sub-skill including args, output JSON schema, constraints.

### Scenario: No-op on clean upstream
**Source:** `skills/push-or-pr/SKILL.md:38-39` — "If there are no pending commits (`noop`), PR args are unused." Also output table at line 44-50: `push_result: "noop"`.
**Interpolated; no direct test.**

### Scenario: Pending commits trigger feature-branch detour
**Source:** `skills/push-or-pr/SKILL.md:7-10` — "saves your commits on a dated feature branch, resets your local copy of that branch to match `origin/<branch>`, pushes the feature branch, and opens a PR". Also `--prefix` description at line 33: "appends `-YYYY-MM-DD` and a numeric suffix on collision".
**Interpolated; no direct test.**

### Scenario: Original branch reset to upstream
**Source:** `skills/push-or-pr/SKILL.md:64-65` — "Never force-push. The script resets the local copy of the branch you were on to its upstream before creating the feature branch."
**Interpolated; no direct test.**

### Scenario: Missing required PR args rejected
**Source:** `skills/push-or-pr/SKILL.md:38` — "If there are pending commits and any of `--prefix` / `--title` / `--body` is missing, the script exits non-zero with exit code 2."
Verified by `assert_invalid_args` cases in `skills/push-or-pr/scripts/test.sh`.

### Scenario: Tags never pushed
**Source:** `skills/push-or-pr/SKILL.md:66` — "The script does not push tags. Tag creation belongs to the caller".
**Interpolated; no direct test.**

---

## Requirement: Develop Sync

**Sources**
- `skills/sync/SKILL.md:1-50` — full skill.

### Scenario: develop checked out and pulled first
**Source:** `skills/sync/SKILL.md:22-29` — "Check out develop and pull the latest from origin (never leave develop stale before the prune/cleanup steps below)".
**Interpolated; no direct test.**

### Scenario: Stale remote refs pruned
**Source:** `skills/sync/SKILL.md:31-35` — `git fetch --prune`.
**Interpolated; no direct test.**

### Scenario: Merged local branches deleted
**Source:** `skills/sync/SKILL.md:37-43` — `git branch --merged develop | grep -vE '^\*|develop|main' | xargs -r git branch -d` — excludes `develop`, `main`, and the current branch.
**Interpolated; no direct test.**

---

## Requirement: Workspace Stash Guard

**Sources**
- `skills/with-clean-workspace/SKILL.md:1-34` — full sub-skill including the Contract section.

### Scenario: Missing -- separator returns usage error
**Source:** `skills/with-clean-workspace/SKILL.md:29` — "Interface: `-- <command ...>`; missing `--` or command exits `2` with stderr usage text."
Verified by `assert_invalid_args` cases in `skills/with-clean-workspace/scripts/test.sh:41-60`.

### Scenario: Tracked + untracked changes stashed
**Source:** `skills/with-clean-workspace/SKILL.md:30` — "stashes tracked + untracked changes (`git stash push -u -m 'flowkit-auto-stash'`)".
Verified by `test_dirty_success_pops_stash` in `skills/with-clean-workspace/scripts/test.sh`.

### Scenario: Stash restored on success
**Source:** `skills/with-clean-workspace/SKILL.md:31` — "Success path: restores stash (`git stash pop`)".
Verified by `test_dirty_success_pops_stash` in `skills/with-clean-workspace/scripts/test.sh`.

### Scenario: Stash kept on pop conflict
**Source:** `skills/with-clean-workspace/SKILL.md:32` — "Pop conflict path: warns to stderr and leaves stash on stack."
Verified by `test_pop_conflict_preserves_stash` in `skills/with-clean-workspace/scripts/test.sh`.

### Scenario: Wrapped command exit code preserved on failure
**Source:** `skills/with-clean-workspace/SKILL.md:33` — "Failure path: keeps stash, warns to stderr, exits with wrapped command's non-zero exit code."
Verified by `test_dirty_failure_preserves_stash` in `skills/with-clean-workspace/scripts/test.sh`.

---

## Requirement: Epic Branch Creation

**Sources**
- `skills/cut-epic/SKILL.md:1-146` — full skill: slug resolution, validation, idempotent branch create, push, pin.

### Scenario: Slug inferred from issue title
**Source:** `skills/cut-epic/SKILL.md:35-41` — `gh issue view "$ISSUE" --json title --jq .title` then kebab-case conversion with `cut -c1-40`.
**Interpolated; no direct test.**

### Scenario: Explicit slug used verbatim
**Source:** `skills/cut-epic/SKILL.md:42` — "If `$ARGUMENTS` contains both a number and a kebab-case word, use them as `<issue>` and `<slug>` regardless of order."
**Interpolated; no direct test.**

### Scenario: Branch name capped at 60 characters
**Source:** `skills/cut-epic/SKILL.md:62` — "The full branch name must be 60 characters or fewer. If the slug pushes it over, truncate the slug, not the issue number."
**Interpolated; no direct test.**

### Scenario: Reserved names rejected
**Source:** `skills/cut-epic/SKILL.md:58-60` — rejection list including `main`, `master`, `develop`, and non-`feature/` prefix.
**Interpolated; no direct test.**

### Scenario: Branch reused if it exists
**Source:** `skills/cut-epic/SKILL.md:72-82` — three-way `if/elif/else` chain handling local-exists, remote-exists, and create-from-develop cases. Constraint at line 144: "Idempotent: re-running with the same arguments must not error".
**Interpolated; no direct test.**

### Scenario: Pin written to claude.flowkit.prBase
**Source:** `skills/cut-epic/SKILL.md:96-98` — `git config claude.flowkit.prBase "$BRANCH"`.
**Interpolated; no direct test.**

---

## Requirement: Epic Promotion

**Sources**
- `skills/ship-epic/SKILL.md:1-82` — full skill including script delegation, output schema, constraints, composition table.

### Scenario: Empty pin and missing --epic stops the skill
**Source:** `skills/ship-epic/SKILL.md:21-26` — "Empty — resolved from `git config --get claude.flowkit.prBase`. If unset or equal to `develop`, the skill stops" with the "No epic in flight" message.
**Interpolated; no direct test.**

### Scenario: Override --epic must start with feature/
**Source:** `skills/ship-epic/SKILL.md:20-22` — `--epic <branch>` "Must start with `feature/` and must not equal `develop`, `main`, or `master`".
Argument validation verified by `assert_invalid_args` cases in `skills/ship-epic/scripts/test.sh`.

### Scenario: Rebase-merge to develop
**Source:** `skills/ship-epic/SKILL.md:69-70` — "Always rebase-merge to `develop`, never squash-merge, never merge-commit. This preserves per-feature first-parent linearity."
**Interpolated; no direct test.**

### Scenario: Closing tokens aggregated from squashes and child PRs
**Source:** `skills/ship-epic/SKILL.md:64` — "Closing-keyword lines aggregated from child squash commits, merged child PR bodies (in case `gh pr merge --squash` dropped the token from the commit message), and the epic issue ref. De-duped case-insensitively."
**Interpolated; no direct test.**

### Scenario: prBase unset and epic branch deleted on success
**Source:** `skills/ship-epic/SKILL.md:43-47` — "`claude.flowkit.prBase` cleared. Local develop fast-forwarded." Plus output table `pr_base_unset` at line 65 and "delete the epic branch" at line 41.
**Interpolated; no direct test.**

### Scenario: Develop fast-forward skipped on different worktree
**Source:** `skills/ship-epic/SKILL.md:51-53` — "If `result.develop_advanced` is `false`, note: Local develop was not fast-forwarded (operator is on a different worktree). Run `/sync` to pull develop."
**Interpolated; no direct test.**

### Scenario: Conflict leaves state intact for retry
**Source:** `skills/ship-epic/SKILL.md:73` — "On rebase-merge conflict: exits 1 with a recovery hint; `claude.flowkit.prBase` and the epic branch are left intact so the operator can rebase and re-invoke."
**Interpolated; no direct test.**

### Scenario: Stacked-PR merge commits stop promotion
**Source:** `skills/ship-epic/SKILL.md:71-72` — "If the epic has no commits ahead of `develop`, or contains raw `worktree-agent-*` merge commits (meaning `swarmkit:merge-stack` was not run), the skill stops with a recovery hint."
**Interpolated; no direct test.**

---

## Requirement: Release Candidate Cut

**Sources**
- `skills/cut/SKILL.md:1-82` — full skill including the N-from-tags computation, refspec collision discussion, brace-the-variable rule.

### Scenario: N derived from existing tags, not branches
**Source:** `skills/cut/SKILL.md:37-43` — `LAST_N=$(git tag --list "rc/$TODAY.*" | grep -oE '\.[0-9]+$' | tr -d '.' | sort -n | tail -1)`. Comment: "tags persist after branch deletion; using max rather than count handles gaps".
**Interpolated; no direct test.**

### Scenario: Always cut from origin/develop
**Source:** `skills/cut/SKILL.md:46-48` — `git checkout -b "$RC_BRANCH" origin/develop`. Constraint at line 79: "Always cut from `origin/develop`, never from a local branch".
**Interpolated; no direct test.**

### Scenario: Tag pushed immediately
**Source:** `skills/cut/SKILL.md:48-54` — branch push, tag, tag push; comment line 54: "The tag is pushed immediately so future cuts count it correctly even after the branch is deleted."
**Interpolated; no direct test.**

### Scenario: Qualified refspec required by tag/branch ambiguity
**Source:** `skills/cut/SKILL.md:56-70` — full discussion of `src refspec matches more than one`, the `git push --force-with-lease origin "refs/heads/${RC_BRANCH}:refs/heads/${RC_BRANCH}"` fix, and the zsh `:r` modifier gotcha requiring `${VAR}` bracing.
**Interpolated; no direct test.**

---

## Requirement: Release to Main

**Sources**
- `skills/release/SKILL.md:1-465` — full skill: rebase, ref aggregation, divergence check, PR body assembly, merge, tag, close loop, cleanup.

### Scenario: No RC branch aborts cleanly
**Source:** `skills/release/SKILL.md:36-39` — `if [ -z "$SOURCE" ]; then echo "release: no rc/* branch ... Run /cut first." >&2; exit 1; fi`. Constraint at line 465.
**Interpolated; no direct test.**

### Scenario: Unconditional rebase onto main
**Source:** `skills/release/SKILL.md:42-52` — full discussion of why this is unconditional (committer-date rewrites from `gh pr merge --rebase`) plus the rebase + force-push.
**Interpolated; no direct test.**

### Scenario: Ancestry assertion after rebase
**Source:** `skills/release/SKILL.md:56-62` — `if ! git merge-base --is-ancestor origin/main "origin/$SOURCE"; then ... exit 1`. "if it fires, something unexpected happened during the rebase".
**Interpolated; no direct test.**

### Scenario: Pre-merge divergence check before opening PR
**Source:** `skills/release/SKILL.md:316-338` — full `git rev-list --left-right --cherry-pick --count` block with remediation message and the "skill does not auto-rebase on the operator's behalf" explanation.
**Interpolated; no direct test.**

### Scenario: Issue refs aggregated since last tag
**Source:** `skills/release/SKILL.md:64-81` — `LAST_TAG` discovery, `TAG_DATE` via python3 ISO conversion, `gh pr list --base develop --state merged --json body,mergedAt` filtered by tag date, grep for closing-keyword footers.
**Interpolated; no direct test.**

### Scenario: Already-closed issues dropped from refs
**Source:** `skills/release/SKILL.md:83-97` — full filter loop with `gh issue view ... --jq '.state'` check and the "Skipped already-closed issue" stderr message.
**Interpolated; no direct test.**

### Scenario: Legacy checklist epics auto-closed when children resolved
**Source:** `skills/release/SKILL.md:100-119` — legacy path: `gh issue list --label "epic"` filtered for `- [ ] #N` bodies, then `OPEN_CHILDREN=$(... grep -oE '- \[ \] #[0-9]+')` and conditional `Closes #$EPIC_N` append.
**Interpolated; no direct test.**

### Scenario: Native sub-issue epics auto-closed when all children resolved
**Source:** `skills/release/SKILL.md:121-165` — sub-issue path: `gh api "repos/$REPO/issues/$EPIC_N/sub_issues"` with `ALL_RESOLVED` check covering both already-closed and in-refs children.
**Interpolated; no direct test.**

### Scenario: Sub-issues fetch failure surfaces non-fatally
**Source:** `skills/release/SKILL.md:135-140` — `if [ $? -ne 0 ]; then echo "$EPIC_N" >> "$SKIPPED_EPICS_FILE" ... continue; fi`. Report covers it at line 458.
**Interpolated; no direct test.**

### Scenario: Release notes grouped by scope
**Source:** `skills/release/SKILL.md:183-198` — `.flowkit/scopes.txt` preferred when present, else auto-detect; full bash logic for both paths.
**Interpolated; no direct test.**

### Scenario: Auto-scope normalization
**Source:** `skills/release/SKILL.md:192-197` — `sed -E 's/^[a-z]+\(([^):/]+).*/\1/'` strips `:sub-scope` portion from `type(scope:sub-scope):` tokens; `sort -u` dedupes.
**Interpolated; no direct test.**

### Scenario: Rebase-merge with delete-branch
**Source:** `skills/release/SKILL.md:344-348` — `gh pr merge "$PR_URL" --rebase --delete-branch`. Constraint at line 464: "Always pass `--rebase --delete-branch` ... Never use `--merge` or `--squash`".
**Interpolated; no direct test.**

### Scenario: Merge wrapped against dirty workspace
**Source:** `skills/release/SKILL.md:342-348` — full discussion of why and the `with-clean-workspace` invocation.
**Interpolated; no direct test.**

### Scenario: Calver tag with collision counter
**Source:** `skills/release/SKILL.md:356-373` — `TAG="v$(date +%Y.%-m.%-d)"` then while-loop incrementing `.N` suffix until free.
**Interpolated; no direct test.**

### Scenario: Per-plugin tags pushed at release
**Source:** `skills/release/SKILL.md:376-397` — full block fetching `*--v*` tags, comparing against origin, pushing missing ones, and the idempotency note.
**Interpolated; no direct test.**

### Scenario: Explicit issue close loop runs regardless of default branch
**Source:** `skills/release/SKILL.md:399-426` — full explanation of why the loop is needed (auto-close only fires on default branch), the idempotent `gh issue close --reason completed`, and the `$EXPLICITLY_CLOSED` reporting variable.
**Interpolated; no direct test.**

### Scenario: RC branch cleanup is the safety net, not the primary cleanup
**Source:** `skills/release/SKILL.md:428-448` — "The primary RC remote-branch cleanup happens in step 6 via `gh pr merge --delete-branch` ... This step is a safety net for RC branches that were ever created but never PR'd".
**Interpolated; no direct test.**

---

## Requirement: Ship Closer

**Sources**
- `skills/ship/SKILL.md:1-89` — full skill: preflight, cut invocation, release invocation, final report.

### Scenario: Open swarm PRs abort ship
**Source:** `skills/ship/SKILL.md:24-42` — full preflight bash: query open PRs against `$BASE`, jq-filter for `worktree-agent-` prefix, exit non-zero with the directive message.
**Interpolated; no direct test.**

### Scenario: Resolved base equals prBase pin
**Source:** `skills/ship/SKILL.md:27` — `BASE=$(git config --get claude.flowkit.prBase 2>/dev/null || echo "develop")`. Discussion at line 47: "If `claude.flowkit.prBase` is set to a `feature/*` branch, that branch is the resolved base".
**Interpolated; no direct test.**

### Scenario: jq-filtered head match
**Source:** `skills/ship/SKILL.md:43-44` — "`gh pr list --head` is exact-match only — it does not support glob patterns ... Filtering the full open-PR set through `jq`'s `startswith` matches the intended prefix semantics."
**Interpolated; no direct test.**

### Scenario: Cut failure aborts before release
**Source:** `skills/ship/SKILL.md:59-60` — "If cut fails (e.g., empty diff against main), stop and report." Also constraint at line 89: "Stop on any sub-skill failure".
**Interpolated; no direct test.**

### Scenario: No internal verify gate
**Source:** `skills/ship/SKILL.md:88` — "No internal verify gate. Ship assumes the operator has already verified the integrated state against the project's tests between merge-stack and ship-epic (or between ship-epic and ship). Ship just packages what is already on develop".
**Interpolated; no direct test.**

---

## Requirement: PR-Base Scope Set/Unset

**Sources**
- `skills/pr-base-scope/SKILL.md:1-43` — full sub-skill.

### Scenario: Set writes the scoped key
**Source:** `skills/pr-base-scope/SKILL.md:14-18` — `git config claude.flowkit.prBase <branch>`.
**Interpolated; no direct test.**

### Scenario: Unset clears the scoped key
**Source:** `skills/pr-base-scope/SKILL.md:28-32` — `git config --unset claude.flowkit.prBase`.
**Interpolated; no direct test.**

### Scenario: Legacy key never written
**Source:** `skills/pr-base-scope/SKILL.md:42` — "Never write to the legacy `claude.prBase` key. All set/unset operations target `claude.flowkit.prBase` only".
**Interpolated; no direct test.**

---

## Requirement: Pipeline Status

**Sources**
- `skills/pipeline-status/SKILL.md:1-128` — full skill: fetch, collect, format, suggest, constraints.

### Scenario: Read-only behavior
**Source:** `skills/pipeline-status/SKILL.md:124` — constraint: "Read-only — never mutate any branch, tag, PR, or label".
**Interpolated; no direct test.**

### Scenario: Fetch precedes any read
**Source:** `skills/pipeline-status/SKILL.md:25-29` — step 1 `git fetch origin`. Constraint at line 125: "Always run `git fetch origin` first so data is current".
**Interpolated; no direct test.**

### Scenario: All four stages always printed
**Source:** `skills/pipeline-status/SKILL.md:53` — "Always print every stage, even if empty — the empty state is itself information. Use 'none' for empty sections." Constraint at line 126.
**Interpolated; no direct test.**

### Scenario: Next step priority order
**Source:** `skills/pipeline-status/SKILL.md:109-118` — priority table mapping conditions to suggestions in first-match-wins order.
**Interpolated; no direct test.**

### Scenario: Draft PRs never trigger a review suggestion
**Source:** `skills/pipeline-status/SKILL.md:120` — "Draft PRs never block the suggestion — they're flagged in the display but skipped in the 'needs review' rule."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **Test coverage is uneven across skills.** `with-clean-workspace/scripts/test.sh` covers all four documented behaviors (invalid usage, dirty-success pop, dirty-failure preserve, pop-conflict preserve) via throwaway git repos. `push-or-pr`, `ship-epic`, `merge-pr`, and `restack` ship argument-validation smoke tests only (`assert_invalid_args`) — their happy paths require live remotes and `gh` auth and are not exercised by the suites. The remaining 14 skills have no automated tests; all their scenarios are interpolated from prose.

2. **Release-cycle ref aggregation relies on PR-body grep, not just commit-message grep.** Step 4 of release scans `gh pr list --json body` rather than `git log` because squash-merges can drop closing-keyword tokens from the commit message footer (line 64-81 of release/SKILL.md). Tests of this behavior would need to exercise the squash/non-squash distinction.

3. **The bubble-free invariant is the load-bearing design constraint.** Multiple skills enforce slices of it (`/merge-pr` rebase-merges to develop, `/ship-epic` rebase-merges epic to develop, `/release` rebase-merges RC to main; all use `--delete-branch`). If any one drifts to squash or merge-commit, `main`'s first-parent line stops being linear and per-feature commits collapse or sprout merge bubbles.

4. **`claude.flowkit.prBase` has three writers and one reader.** Writers: `cut-epic` (set to feature branch), `pr-base-scope` Set (set arbitrary), `swarmkit:swarm` loop mode preflight (set to base) — all via direct `git config` rather than going through `pr-base-scope`. Unsetters: `ship-epic` (on success), `pr-base-scope` Unset, `swarmkit:swarm` teardown (non-epic mode). Reader: `open-pr`'s base-resolution chain. This is the single piece of cross-skill shared state in flowkit.

5. **The default-branch nudge is silent in steady state.** Once `claude.flowkit.defaultBranchPrompted` is `true`, the sub-skill always exits in step 1 without printing anything. The skill is intentionally designed to be loud once and silent forever after.

6. **Reusing `cut-epic` with the same arguments is the supported resume path.** Idempotency is built in: if the branch exists locally or on origin, it is checked out and the pin is refreshed (lines 72-82, 144). Operators who get interrupted mid-epic can re-run `cut-epic` and continue.

7. **`gh pr list --head` is exact-match only.** This is a GitHub CLI behavior, not a flowkit choice — but ship/SKILL.md (line 43) documents it because the prior code used `--head 'worktree-agent-*'` and silently returned empty. Anywhere else in flowkit (and downstream skills) that needs prefix matching against PR head branches must do it via `gh pr list --json headRefName` + `jq startswith`.

8. **release-step-3's rebase target is the short-lived RC, never main.** This is called out at line 46 of release/SKILL.md to defuse the obvious worry about force-pushing during a release. The RC branch is deleted minutes later by `gh pr merge --delete-branch` in step 6, so even the worst-case race is bounded.
