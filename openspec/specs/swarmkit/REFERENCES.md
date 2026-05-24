# swarmkit — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `plugins/swarmkit/` unless otherwise noted.
Line numbers verified on 2026-05-23.

---

## Requirement: Issue Fetching and Filtering

**Sources**
- `skills/gh-fetch-issues/SKILL.md:16-21` — defines the canonical fetch command and the two filter rules: exclude `on-hold` and `status:in-progress` labeled issues.

**Notes**
- Both filters apply in every caller context (next-issue, swarm one-shot, loop mode). The `gh issue list --search '-label:"status:in-progress"'` flag handles the in-progress exclusion at the API level; the `on-hold` exclusion is a post-fetch filter rule in the same sub-skill.

### Scenario: On-hold issues excluded
**Source:** `skills/gh-fetch-issues/SKILL.md:17-18` — "Filter out any issue with the `on-hold` label".
Verified by behavior in `skills/swarm/SKILL.md:374-379` (loop mode picks batch using gh-fetch-issues).
**Interpolated; no direct test.**

### Scenario: In-progress issues excluded
**Source:** `skills/gh-fetch-issues/SKILL.md:14-15` — `--search '-label:"status:in-progress"'` in the `gh issue list` command; also `skills/gh-fetch-issues/SKILL.md:20-21` — prose rule.
**Interpolated; no direct test.**

---

## Requirement: Issue Ranking

**Sources**
- `skills/issue-rank/SKILL.md:1-34` — full ranking table and assessment criteria.

### Scenario: Priority labels respected
**Source:** `skills/issue-rank/SKILL.md:8-15` — ranking table: `priority:high` → highest, `priority:medium` → high, `priority:low` → low, no label → medium (read body to judge).
**Interpolated; no direct test.**

### Scenario: Specificity and impact favor architectural unblocking
**Source:** `skills/issue-rank/SKILL.md:21-24` — assessment criteria: specificity (exact files, line numbers), architectural impact (unblocks other work), and the note on line 30: "A well-specced `priority:medium` issue often beats a vague `priority:high` one for autonomous agent work".
**Interpolated; no direct test.**

---

## Requirement: One-Shot Mode

**Sources**
- `skills/swarm/SKILL.md:99-349` — full one-shot mode section (steps 1–7).
- `skills/swarm/SKILL.md:100-138` — gather script invocation, work_items parsing, skip announcements, unwired-epic handling.

### Scenario: Closed and on-hold issues skipped from requested set
**Source:** `skills/swarm/SKILL.md:122-131` — "Parse the JSON. Use `work_items` as the list to act on" and "Skip announcement — for each entry in `skipped`, the script has already applied the existing rules (`on-hold` label, `closed` state)."
**Interpolated; no direct test.**

### Scenario: Epic expansion
**Source:** `skills/swarm/SKILL.md:121-131` — `epics_expanded` field in gather script output, skip announcement template: "#N is an epic. Swarming: #101, #102. Skipped (closed/on-hold): #103."
**Interpolated; no direct test.**

### Scenario: Unwired epic skipped with guidance
**Source:** `skills/swarm/SKILL.md:133-137` — "for each number in `epics_unwired`, announce with the existing template" citing the `#N is labeled epic but has no sub-issues wired` message.
**Interpolated; no direct test.**

### Scenario: Empty work set stops dispatch
**Source:** `skills/swarm/SKILL.md:132` — "If `work_items` is empty because every requested issue ... was skipped, announce and stop."
**Interpolated; no direct test.**

### Scenario: Plan presented before dispatch
**Source:** `skills/swarm/SKILL.md:158-173` — "Show the user a table before launching" with columns Agent, Issue(s), Branch, Files affected, Model, Notes; also "Present the plan and proceed immediately with the proposed groupings."
**Interpolated; no direct test.**

---

## Requirement: Dependency Graph and Topological Dispatch

**Sources**
- `skills/swarm/SKILL.md:140-156` — dependency analysis: use `deps` array from gather script (native `blockedBy` preferred, body-text fallback), build DAG, topological sort.
- `skills/swarm/SKILL.md:197-218` — spawn strategy: independent in parallel, dependent sequential in topological order, branching from upstream tip.
- `METHODOLOGY.md:41-65` — narrative on stacked branch strategy and why mid-swarm merge is forbidden.

### Scenario: Independent issues spawn in parallel
**Source:** `skills/swarm/SKILL.md:198-202` — "Independent issues (no dependencies within this batch): Spawn all in parallel … `run_in_background: true`".
**Interpolated; no direct test.**

### Scenario: Dependent agent branches from upstream tip
**Source:** `skills/swarm/SKILL.md:206-211` — "The dependent agent branches from its dependency's branch tip … `git fetch origin worktree-agent-<dependency-issue>; git checkout -b worktree-agent-<this-issue> origin/worktree-agent-<dependency-issue>`".
Also `METHODOLOGY.md:43-56`.
**Interpolated; no direct test.**

### Scenario: Dependent agent PR targets upstream branch
**Source:** `skills/swarm/SKILL.md:212-215` — "The dependent agent's PR targets the dependency's branch … `gh pr create --base worktree-agent-<dependency-issue>`".
**Interpolated; no direct test.**

### Scenario: Mid-swarm merge forbidden
**Source:** `skills/swarm/SKILL.md:218-219` — "Why no mid-swarm merge is needed … Never merge a dependency's PR early to 'unblock' a downstream agent." Also `skills/swarm/SKILL.md:456-458` — constraint: "Never merge a PR mid-swarm".
Also `METHODOLOGY.md:62-66`.
**Interpolated; no direct test.**

---

## Requirement: Worktree Isolation

**Sources**
- `skills/swarm/SKILL.md:222-224` — all agents use `isolation: "worktree"`, `mode: "bypassPermissions"`, `run_in_background: true`.
- `skills/swarm/SKILL.md:228-231` — agent CONTEXT instruction: "use relative paths only for all file operations".
- `skills/swarm/SKILL.md:244-248` — safety check: `[[ "$PWD" != *"worktrees"* ]] && echo "ERROR…" && exit 1`.
- `skills/swarm/SKILL.md:249-261` — ancestry check: `git merge-base --is-ancestor origin/<base> HEAD` with abort on failure.
- `METHODOLOGY.md:31-38` — narrative on worktree isolation and why relative paths are required.

### Scenario: Worktree safety check aborts on wrong directory
**Source:** `skills/swarm/SKILL.md:244-248` — `[[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not running in an isolated worktree. Aborting to prevent branch collision." && exit 1`.
**Interpolated; no direct test.**

### Scenario: Ancestry check aborts on stale base
**Source:** `skills/swarm/SKILL.md:249-261` — `if ! git merge-base --is-ancestor origin/<base> HEAD; then echo "ERROR: HEAD is not a descendant of origin/<base>. Worktree may be rooted on a stale base." >&2 … exit 1; fi`. Comment at line 251 identifies the motivating bug: post-rebase-merge worktree-base drift (#923).
**Interpolated; no direct test.**

### Scenario: Relative paths enforced
**Source:** `skills/swarm/SKILL.md:228-231` — "Instruct agents that their CWD is the repo root — use relative paths only for all file operations … Do NOT include the absolute repo path."
Also constraint `skills/swarm/SKILL.md:455-457`: "Never pass absolute repo paths to spawned agents".
**Interpolated; no direct test.**

---

## Requirement: PR Creation Standards

**Sources**
- `skills/swarm/SKILL.md:264-300` — agent workflow steps 3–5: commit format, push, PR creation with body template.
- `skills/swarm/SKILL.md:300` — "This is the ONLY acceptable termination condition for this workflow."
- `skills/conventional-commit-message/SKILL.md:1-35` — conventional commit format, type enum, subject length.

### Scenario: Branch naming convention
**Source:** `skills/swarm/SKILL.md:224` — "Branch naming: `worktree-agent-<issue>` (required for `clean-worktrees`)".
Also `README.md:162-164` — "Every agent branch follows this exact pattern … It is not configurable."
**Interpolated; no direct test.**

### Scenario: PR body standard sections
**Source:** `skills/swarm/SKILL.md:275-300` — PR body template showing `## Summary`, `## Test plan`, and `Closes #<issue>` footer.
**Interpolated; no direct test.**

### Scenario: Conventional commit format
**Source:** `skills/swarm/SKILL.md:263-265` — "Stage and commit using conventional-commit-message format … `git add <files> && git commit -m '<type>(<scope>): <description>'"`. Sub-skill `skills/conventional-commit-message/SKILL.md:1-35`.
**Interpolated; no direct test.**

### Scenario: PR termination only after PR URL reported
**Source:** `skills/swarm/SKILL.md:300` — "Report the PR URL. This is the ONLY acceptable termination condition for this workflow. Do not stop before the PR exists and its URL has been reported."
**Interpolated; no direct test.**

---

## Requirement: Issue Labeling

**Sources**
- `skills/swarm/SKILL.md:183-193` — before spawning each agent: create label if missing, then `gh issue edit <issue> --add-label "status:in-progress"`.
- `README.md:178-184` — "When an agent is spawned for an issue, swarmkit applies `status:in-progress` to it."

### Scenario: Label created if absent
**Source:** `skills/swarm/SKILL.md:185-188` — `gh label list | grep -q "status:in-progress" || gh label create "status:in-progress" --description "Actively being worked on" --color "E4E669"`.
**Interpolated; no direct test.**

### Scenario: Label applied before dispatch
**Source:** `skills/swarm/SKILL.md:183-190` — full block: label existence check, creation if absent, then `gh issue edit <issue> --add-label "status:in-progress"` immediately before spawn.
**Interpolated; no direct test.**

### Scenario: Issue never closed by swarm
**Source:** `skills/swarm/SKILL.md:448-449` — constraint: "Never close issues — issues are closed by the release process when the release merges to main".
Also `README.md:182-184`.
**Interpolated; no direct test.**

---

## Requirement: Feature-Branch Mode

**Sources**
- `skills/swarm/SKILL.md:22-58` — epic mode resolution: EPIC_MODE logic, slug derivation table, empty-board edge case, cross-pin guard, cut-epic invocation.
- `skills/swarm/SKILL.md:73-93` — preflight with `--scope-pr-base` when EPIC_MODE=on.
- `skills/swarm/SKILL.md:399-416` — teardown: `--keep-pr-base` in epic mode, announcement of remaining pin.
- `METHODOLOGY.md:92-168` — full feature-branch mode narrative including trigger rule, slug derivation, loop-mode reuse, ship-epic handoff, escape hatches, cross-pin guard, squadkit symmetry.

### Scenario: Multi-issue one-shot cuts epic branch
**Source:** `skills/swarm/SKILL.md:23-24` — "When the run will spawn ≥2 agents … swarm cuts a `feature/<slug>-<N>` branch via `flowkit:cut-epic`". EPIC_MODE logic at lines 33-38: one-shot AND issue_count==1 → off; otherwise → on.
Also `METHODOLOGY.md:94-100`.
**Interpolated; no direct test.**

### Scenario: Loop mode cuts epic at first non-empty cycle
**Source:** `skills/swarm/SKILL.md:47-48` — "defer the cut-epic invocation until the first cycle that selects ≥1 issue." Also `METHODOLOGY.md:123-127`.
**Interpolated; no direct test.**

### Scenario: Single-issue one-shot stays flat
**Source:** `skills/swarm/SKILL.md:34-35` — `elif arg-mode == one-shot AND issue_count == 1: EPIC_MODE=off`.
Also `METHODOLOGY.md:101-102`.
**Interpolated; no direct test.**

### Scenario: --no-epic suppresses the cut
**Source:** `skills/swarm/SKILL.md:33-34` — `elif --no-epic is set: EPIC_MODE=off`.
Also `METHODOLOGY.md:154-155`.
**Interpolated; no direct test.**

### Scenario: --base suppresses the cut
**Source:** `skills/swarm/SKILL.md:32-33` — `if --base is set: EPIC_MODE=off`.
Also `METHODOLOGY.md:156-157`.
**Interpolated; no direct test.**

### Scenario: Empty board in loop mode skips cut
**Source:** `skills/swarm/SKILL.md:47-48` — "If the board is clear at loop entry, announce 'Board is clear' and exit without cutting any branch."
Also `METHODOLOGY.md:124-127`.
**Interpolated; no direct test.**

### Scenario: Cross-pin guard prevents silent overwrite
**Source:** `skills/swarm/SKILL.md:50-52` — cross-pin defensive guard: read `claude.flowkit.prBase`; if set AND starts with `feature/` AND differs from branch about to be cut, exit with error message.
Also `METHODOLOGY.md:159-164`.
**Interpolated; no direct test.**

### Scenario: cut-epic is idempotent on resume
**Source:** `skills/swarm/SKILL.md:53-54` — "cut-epic is idempotent — if the branch already exists locally or on origin it is reused and the pin is refreshed."
Also `METHODOLOGY.md:106-108`.
**Interpolated; no direct test.**

---

## Requirement: Loop Mode

**Sources**
- `skills/swarm/SKILL.md:354-443` — full loop mode section: setup, loop cycle, checkpoint, teardown, smart failure rules.
- `METHODOLOGY.md:79-90` — loop mode and failure handling narrative.

### Scenario: Batch selection avoids file conflicts
**Source:** `skills/swarm/SKILL.md:373-378` — batch selection criteria: "No two issues touch the same files; No unresolved dependencies within the batch."
Also `METHODOLOGY.md:82-84`.
**Interpolated; no direct test.**

### Scenario: Checkpoint printed after each cycle
**Source:** `skills/swarm/SKILL.md:384-396` — checkpoint block format with PRs opened, failed, blocked, remaining; and "Proceed immediately to the next cycle after printing the checkpoint summary."
**Interpolated; no direct test.**

### Scenario: Failed issue blocks dependents in subsequent cycles
**Source:** `skills/swarm/SKILL.md:433-438` — "Check all remaining issues in current and future cycles for file overlap or explicit references to the failed issue; Mark those as blocked; continue with all unblocked issues."
Also `METHODOLOGY.md:83-87`.
**Interpolated; no direct test.**

### Scenario: Agent crash with no PR is unrecoverable
**Source:** `skills/swarm/SKILL.md:439-440` — "Unrecoverable failures (exit loop immediately): Agent produced no PR (crash, timeout, no push)".
Also `METHODOLOGY.md:85-87`.
**Interpolated; no direct test.**

### Scenario: Base branch deletion is unrecoverable
**Source:** `skills/swarm/SKILL.md:441-442` — "`$BASE` branch deleted or corrupted externally".
**Interpolated; no direct test.**

### Scenario: prBase config cleaned up on teardown
**Source:** `skills/swarm/SKILL.md:399-416` — teardown: `teardown.sh --base "$BASE"` in non-epic mode; "Leaving it set will cause subsequent PR creation (even in unrelated workflows) to target the wrong base."
Also `METHODOLOGY.md:88-90`.
**Interpolated; no direct test.**

### Scenario: prBase kept on teardown in epic mode
**Source:** `skills/swarm/SKILL.md:401-414` — `teardown.sh --keep-pr-base` in epic mode; `config_kept_for_epic: true` JSON field triggers announcement: "Epic branch `<EPIC_BRANCH>` is left in place with `claude.flowkit.prBase` pinned. Run `/ship-epic` to promote it…"
Also `METHODOLOGY.md:129-148`.
**Interpolated; no direct test.**

---

## Requirement: Bottom-Up Stack Merge

**Sources**
- `skills/merge-stack/SKILL.md:1-222` — full merge-stack skill.
- `METHODOLOGY.md:68-77` — bottom-up merge with up-front retargeting narrative.

### Scenario: Only worktree-agent-* PRs are included
**Source:** `skills/merge-stack/SKILL.md:22-29` — `gh pr list … --jq '.[] | select(.headRefName | startswith("worktree-agent-"))'`.
**Interpolated; no direct test.**

### Scenario: Non-root PRs retargeted before first merge
**Source:** `skills/merge-stack/SKILL.md:49-57` — step 3: "retarget every non-root PR to `$BASE` before merging anything." `gh pr edit <N> --base $BASE`.
Also `METHODOLOGY.md:68-73`.
**Interpolated; no direct test.**

### Scenario: Independent PRs merge in any order
**Source:** `skills/merge-stack/SKILL.md:41-45` — "Independent PRs: PRs whose `baseRefName` is already `$BASE` and that no other PR sits on top of — these have no stack relationship and can merge in any order."
Also constraint `skills/merge-stack/SKILL.md:219`: "Independent PRs (targeting `$BASE` with nothing stacked on them) may merge in any order".
**Interpolated; no direct test.**

### Scenario: Downstream PRs rebased after predecessor merges
**Source:** `skills/merge-stack/SKILL.md:7-15` — introductory explanation of the rebase step and why it is necessary. Step 5e at lines `skills/merge-stack/SKILL.md:155-169` — uses `flowkit:restack` script to rebase each downstream branch onto `origin/$BASE`; `git rebase` patch-id matching drops predecessor commits.
**Interpolated; no direct test.**

### Scenario: Malformed closing-keyword footer warned before merge
**Source:** `skills/merge-stack/SKILL.md:119-130` — step 5b: grep body for space-separated form; emit warning to stderr; merge proceeds without blocking.
**Interpolated; no direct test.**

### Scenario: Conflict stops chain and blocks dependents
**Source:** `skills/merge-stack/SKILL.md:143-151` — step 5d: "Stop the chain at this PR; Report the conflict; Mark all PRs above it in the same chain as blocked; Continue with any independent PRs or unrelated chains."
**Interpolated; no direct test.**

### Scenario: No PR found stops cleanly
**Source:** `skills/merge-stack/SKILL.md:27-29` — "If no open swarm PRs are found, report 'No open swarm PRs found' and stop."
**Interpolated; no direct test.**

---

## Requirement: Swarm-Plus Review/Fix Pass

**Sources**
- `skills/swarm-plus/SKILL.md:1-209` — full swarm-plus skill.
- `agents/swarm-reviewer.md:1-87` — reviewer agent definition, output format, verdict delivery contract.
- `METHODOLOGY.md:207-219` — swarm-plus narrative.

### Scenario: Reviewer dispatched as swarm agent completes
**Source:** `skills/swarm-plus/SKILL.md:73-78` — "Do NOT block on every swarm agent before spawning reviewers. As each swarm agent's task notification arrives: Verify the PR exists … Spawn a reviewer for that PR … Continue handling other notifications in parallel."
**Interpolated; no direct test.**

### Scenario: Skip-on-clean rule
**Source:** `skills/swarm-plus/SKILL.md:103-106` — table row: "Verdict `Approve` AND no blockers AND no concerns AND no `[recommended]` coverage gaps → No fix-round worker."
Also `METHODOLOGY.md:211-212`.
**Interpolated; no direct test.**

### Scenario: Blocker or concern triggers fresh worker
**Source:** `skills/swarm-plus/SKILL.md:107-112` — table rows: blockers, concerns, `[recommended]` gaps each trigger a fresh worker. Lines 121-122: "spawn a fresh `general-purpose` agent … The original builder is never re-engaged."
Also `METHODOLOGY.md:212-213`.
**Interpolated; no direct test.**

### Scenario: Worker branches from existing PR head
**Source:** `skills/swarm-plus/SKILL.md:134-136` — "Branch from the existing PR branch, NOT from `develop`: `git fetch origin <head_branch>; git checkout -B <head_branch> origin/<head_branch>`".
**Interpolated; no direct test.**

### Scenario: Nits and optional gaps never trigger a worker
**Source:** `skills/swarm-plus/SKILL.md:103-106` — table: nits and `[optional]` gaps produce no fix-round worker. Also `METHODOLOGY.md:213-214`.
**Interpolated; no direct test.**

### Scenario: --review-only suppresses fix-round workers
**Source:** `skills/swarm-plus/SKILL.md:109-110` — "`--review-only` flag set → Never spawn a fix-round worker, regardless of reviewer verdict."
**Interpolated; no direct test.**

### Scenario: Worker must not push a failing build
**Source:** `skills/swarm-plus/SKILL.md:136-138` — "Run `<verify_command>` … Resolve any failures before proceeding — never push a red build."
Also constraint at `skills/swarm-plus/SKILL.md:194-195`.
**Interpolated; no direct test.**

### Scenario: Single pass per PR
**Source:** `skills/swarm-plus/SKILL.md:174-176` — constraint: "Single pass — no reviewer-after-fix re-review. The user can manually trigger another review with `/review <pr>` if desired."
Also `METHODOLOGY.md:215-217`.
**Interpolated; no direct test.**

### Scenario: Reviewer output never posted as PR comment
**Source:** `agents/swarm-reviewer.md:71-72` — critical constraint: "Return the review inline. Never post it as a `gh pr comment`."
Also `skills/swarm-plus/SKILL.md:181`: "Reviewer output stays inline, never posted as a PR comment by the reviewer itself."
**Interpolated; no direct test.**

### Scenario: Swarm agent failure skips review
**Source:** `skills/swarm-plus/SKILL.md:187-189` — failure mode table: "Swarm agent fails to produce a PR → Skip review/fix round for that issue; report in final summary."
**Interpolated; no direct test.**

---

## Requirement: Local Worktree Cleanup

**Sources**
- `skills/clean-worktrees/SKILL.md:1-113` — full clean-worktrees skill.

### Scenario: Stuck worktrees block cleanup
**Source:** `skills/clean-worktrees/SKILL.md:47-56` — "Parse the `stuck` array. If it is non-empty, stop immediately and report … Do not proceed to removal if `stuck` is non-empty."
**Interpolated; no direct test.**

### Scenario: Nothing to clean reported cleanly
**Source:** `skills/clean-worktrees/SKILL.md:60-65` — "If both `worktrees_to_remove` and `branches_to_delete` are empty arrays, report: Nothing to clean — no agent worktrees or orphaned branches found."
**Interpolated; no direct test.**

### Scenario: Caller branch restored after cleanup
**Source:** `skills/clean-worktrees/SKILL.md:98-113` — report section includes "Caller branch: restored to `<caller_branch>` / skipped (branch was removed)". Lines 108-110: warning if `caller_branch_restored` is `false`.
**Interpolated; no direct test.**

---

## Requirement: Remote Branch Cleanup

**Sources**
- `skills/clean-remote-worktrees/SKILL.md:1-153` — full clean-remote-worktrees skill.

### Scenario: Merged branches deleted
**Source:** `skills/clean-remote-worktrees/SKILL.md:43-44` — classify script output: `"state": "MERGED"` entries land in the `merged` array; step 5 deletes exactly the `merged` array.
**Interpolated; no direct test.**

### Scenario: Open PR branches skipped
**Source:** `skills/clean-remote-worktrees/SKILL.md:144-146` — constraint: "Never delete a branch that is the head of an OPEN PR."
**Interpolated; no direct test.**

### Scenario: Closed-non-merged branches preserved
**Source:** `skills/clean-remote-worktrees/SKILL.md:147-148` — constraint: "Never delete a branch whose most-recent PR is CLOSED (non-merged) — the branch contains rejected work that persists nowhere else."
**Interpolated; no direct test.**

### Scenario: No-PR branches surfaced for manual inspection
**Source:** `skills/clean-remote-worktrees/SKILL.md:149-150` — constraint: "Never delete a branch with no associated PR — surface it for manual inspection."
Also output template at `skills/clean-remote-worktrees/SKILL.md:131-140`: "No PR (inspect manually):" section.
**Interpolated; no direct test.**

### Scenario: Interactive mode confirms before deletion
**Source:** `skills/clean-remote-worktrees/SKILL.md:99-104` — step 4: "In interactive mode (no `--yes`), ask before proceeding: 'Proceed with deleting <count> remote branch(es)?' … If the user declines, stop without deleting anything."
**Interpolated; no direct test.**

### Scenario: --yes enables non-interactive deletion
**Source:** `skills/clean-remote-worktrees/SKILL.md:105-106` — "With `--yes`, skip the prompt and proceed immediately."
**Interpolated; no direct test.**

### Scenario: Idempotent on clean repo
**Source:** `skills/clean-remote-worktrees/SKILL.md:59-62` — step 2: "If `candidates` is an empty array, report: No remote `worktree-agent-*` branches found." Also constraint `skills/clean-remote-worktrees/SKILL.md:152`: "Idempotent: running twice on a clean repo is a no-op."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **All scenarios are interpolated from code/prose; no automated tests exist.** The `skills/*/scripts/test.sh` files exist for swarm, clean-worktrees, and clean-remote-worktrees but are shell-level unit tests for script helpers, not behavioral tests for the skill scenarios themselves.

2. **Feature-branch mode uses different thresholds for one-shot vs. loop mode.** One-shot requires ≥2 issue numbers to trigger the epic cut; loop mode cuts at the first cycle that selects ≥1 issue. This asymmetry is documented in `METHODOLOGY.md:94-101` ("any board with ≥1 issue → epic cut at first non-empty cycle") and the spec's Feature-Branch Mode requirement. It is intentional design, not an edge case.

3. **`claude.flowkit.prBase` pin scope is the local git config, not a shell variable.** The pin persists across agent invocations and tool calls within the session. Teardown must unset it or the scope bleeds into unrelated PR commands — cited in `METHODOLOGY.md:88-90` and teardown prose in `skills/swarm/SKILL.md:368`.

4. **Reviewer verdict delivery uses `SendMessage`, not just the idle notification.** `skills/swarm-plus/SKILL.md:93-96` and `agents/swarm-reviewer.md:78-86` both state that the structured verdict must be sent via `SendMessage` before the reviewer terminates; the idle notification alone does not carry the verdict. This timing contract has no test coverage and is critical to the skip-on-clean logic.

5. **Builder agents are treated as non-addressable post-PR.** `skills/swarm-plus/SKILL.md:16-22` documents that `SendMessage` to a former builder consistently fails under the current runtime. The `STANDBY_READY` sentinel and STANDBY clause in builder prompts are forward-compatibility stubs only. Any future runtime change that makes builders addressable would change this behavior.

6. **worktree-agent-* branch naming is load-bearing.** Both `clean-worktrees` (local) and `clean-remote-worktrees` (remote) and `merge-stack` all key on this prefix. The convention is documented as "not configurable" in `README.md:162-166`.
