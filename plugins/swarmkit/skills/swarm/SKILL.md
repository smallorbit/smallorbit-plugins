---
name: swarm
description: Spawn parallel isolated-worktree agents for GitHub issues, open stacked PRs in dependency order, run an automatic review/fix pass over each PR, and leave them open for review. Use `swarmkit:merge-stack` to merge. Supports one-shot mode (specific issue numbers) and loop mode (clear the board continuously).
---

# Swarm Skill

> See the swarmkit README's [Permissions](../../README.md#permissions) section for session-level permission guidance before first use.

Spawn parallel agents for GitHub issues: $ARGUMENTS

Every PR swarm opens passes through an automatic review/fix pass before the run completes: a swarmkit-vendored reviewer inspects each PR, and if the reviewer surfaces blockers, concerns, or `[recommended]` coverage gaps, a fresh worker is spawned to push follow-up commits to the same branch. This is always-on — there is no flag to disable it. The final state is unchanged: open PRs awaiting human merge.

### Runtime contract: builders always exit; fix-rounds always spawn a fresh worker

The harness terminates builder agents shortly after they emit their final task notification. Builder prompts still emit `STANDBY_READY` as a forward-compatibility hint in case the runtime ever supports persistent standby, but **the orchestrator MUST treat every builder as no-longer-addressable once the PR is reported**. SendMessage to a former builder consistently fails with "No agent named X is currently addressable."

**Canonical fix-round path: spawn-fresh-worker.** Whenever a reviewer's verdict is non-clean (blockers, concerns, or `[recommended]` coverage gaps), the orchestrator spawns a brand-new `general-purpose` agent in an isolated worktree, branches it from the existing PR head, and lets it apply the reviewer's findings. The original builder is never re-engaged.

**Why STANDBY_READY remains in builder prompts.** It is cheap, harmless under today's runtime (the builder emits the sentinel and is then terminated by the harness), and keeps the prompt forward-compatible if a future runtime version preserves agents past their last notification. The orchestrator should NOT attempt SendMessage on builders today — those calls will fail.

## Arguments

Parse `$ARGUMENTS` to determine the mode:

- **No arguments** → **loop mode**, all open issues → `main`
- **Label text** (non-numeric, e.g. `bug`, `priority:high`) → **loop mode**, filtered by label → `main`
- **Issue numbers** (`12 15 18`, `#12 #15 #18`, range `12-18`) → **one-shot mode**, specific issues → `main`
- `--model <tier>` (`sonnet`, `opus`) → model override for all builder agents
- `--base <branch>` → override default base branch
- `--no-epic` → suppress feature-branch mode for this run; PRs target `$BASE` directly
- `--epic <slug>` → explicit slug for the auto-cut epic branch (the inline cut enforces the `feature/<slug>-<N>` shape)
- `--reviewer-model <tier>` → override the review-pass reviewer model (default: `sonnet`)
- `--worker-model <tier>` → override the fix-round worker model (default: `sonnet`)

---

## Epic Mode Resolution

Compute `EPIC_MODE` before any setup work:

```
if --base is set:                                  EPIC_MODE=off
elif --no-epic is set:                             EPIC_MODE=off
elif arg-mode == one-shot AND issue_count == 1:    EPIC_MODE=off
else:                                              EPIC_MODE=on
```

### When EPIC_MODE=on

**Resolve the branch name** `EPIC_BRANCH` (in order):

1. `--epic <slug>` arg → if it already starts with `feature/`, use verbatim; otherwise prepend `feature/`.
2. One-shot multi-issue → derive slug from the lowest issue number's title (`gh issue view <N> --json title --jq '.title'`), kebab-case it (lowercase; non-alphanumerics → `-`; collapse runs; trim leading/trailing `-`), and form `feature/<slug>-<lowest-issue>`.
3. Loop mode (no label) → `feature/swarm-$(date +%Y-%m-%d)`.
4. Loop mode + label → `feature/<label>-$(date +%Y-%m-%d)`.

**Empty-board edge case (loop mode only)**: defer the inline cut until the first cycle that selects ≥1 issue. If the board is clear at loop entry, announce "Board is clear" and exit without cutting any branch.

**Cross-pin defensive guard**: the durable enforcement lives in `preflight.sh` — when invoked with `--scope-pr-base`, it reads `claude.flowkit.prBase` and, if the pin is set AND starts with `feature/` AND differs from the branch about to be pinned, exits non-zero with the guidance message below. This protects any direct caller of `preflight --scope-pr-base`, not just this prose path. The expected message is:

> `swarm: an epic is already pinned (\`<existing>\`); pass \`--no-epic\` to swarm against main, or \`--epic <existing-slug>\` to reuse the pinned branch.`

**Cut the feature branch inline** with `git`/`gh`. This is idempotent — if the branch already exists on origin, fetch and check it out instead of recreating, and refresh the pin:

```bash
git fetch origin main
if git ls-remote --exit-code --heads origin "$EPIC_BRANCH" >/dev/null 2>&1; then
  # Resume path — branch exists on origin
  git fetch origin "$EPIC_BRANCH"
  git checkout -B "$EPIC_BRANCH" "origin/$EPIC_BRANCH"
else
  # First cut — branch off main and push
  git checkout -B "$EPIC_BRANCH" origin/main
  git push -u origin "$EPIC_BRANCH"
fi
# Setup's `preflight.sh --scope-pr-base` re-asserts this pin under the
# cross-pin guard; this inline write keeps the resume path consistent.
git config claude.flowkit.prBase "$EPIC_BRANCH"
```

Announce the result:

> Cut `<EPIC_BRANCH>` from `origin/main` and pinned `claude.flowkit.prBase`. All PRs will target `<EPIC_BRANCH>`.

(If the branch already existed and was reused, swap the verb: `Resumed <EPIC_BRANCH> on origin and refreshed pin.`)

### When EPIC_MODE=off

Skip the cut. `EPIC_BRANCH` is unset; PRs target `$BASE` directly. Behavior is identical to today's flat-to-`$BASE` flow.

---

## Setup

Capture the harness-emitted `Base directory for this skill:` path as `SKILL_DIR`; use `"$SKILL_DIR/scripts/..."` for every script invocation below.

Run the preflight script once. It handles fetch, base-branch verification (creating it from `main` and pushing if missing), and `gh` auth check in a single call:

```bash
if [ "$EPIC_MODE" = "on" ] || [ "$LOOP_MODE" = "on" ]; then
  "$SKILL_DIR/scripts/preflight.sh" --base "${EPIC_BRANCH:-$BASE}" --scope-pr-base
else
  "$SKILL_DIR/scripts/preflight.sh" --base "$BASE"
fi
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{"base": "main", "base_existed": true, "base_created": false, "gh_authenticated": true, "repo": "owner/name"}
```

Parse the JSON. If `gh_authenticated` is `false`, **stop immediately** and surface the script's stderr to the user — no swarm work can proceed without `gh` auth. If `base_created` is `true`, announce:

> Created `<base>` branch from the repo's default branch. All PRs will target `<base>`.

If the script exits non-zero, stdout will be empty and stderr will carry a human-readable error — surface it and stop.

### Resolve the verify command (for the review/fix pass)

> Resolved once at the start of the run, before any worker is dispatched.

The fix-round workers need the project's verify command. Resolve it once and reuse it for every fix-round prompt. This keeps the review pass useful in any repo, not just TS repos with `tsc`. Use this lookup chain (first hit wins):

1. **`.squadkit/config.json` `verifyCommand`** — repo-level explicit override. Read with `jq -r '.verifyCommand // empty' .squadkit/config.json` if the file exists.
2. **`package.json` `scripts.verify`** — common project-local convention. If present, the verify command is determined by the package manager: `yarn.lock` present → `yarn run verify`; `pnpm-lock.yaml` present → `pnpm run verify`; otherwise → `npm run verify`.
3. **Fallback** — `npx tsc -b --noEmit` for TS projects. "TS toolchain present" means `tsconfig.json` exists at the repo root. If neither of the above resolves AND `tsconfig.json` is absent, print a warning and instruct the worker to skip the verify step rather than running a command that will obviously fail. **Note:** projects that use `tsc` via a non-standard mechanism (e.g. a wrapper script, a monorepo tool, or a config file named differently) won't be detected by this check — those repos should set `verifyCommand` in `.squadkit/config.json` to opt in explicitly.

Record the resolved command as `<verify_command>` and interpolate it into the STANDBY clause (Step 4 spawn) and the fix-round worker prompt (Review/Fix Pass step 3).

---

## One-Shot Mode

Used when issue numbers are provided. Dispatches agents for the given set of issues, opens PRs, and reports. Use `swarmkit:merge-stack` to merge.

### 1. Gather issue details

Run the gather script once with all requested issue numbers. It batches title, body, labels, state, sub-issues, and native dependency edges (`blockedBy`) into a single `gh api graphql` call, collapsing what was ~3N bash turns into one script invocation:

```bash
"$SKILL_DIR/scripts/gather_issues.sh" <number> [<number> ...]
```

On success the script exits 0 and emits one JSON object on stdout:

```json
{
  "requested": [544, 545],
  "work_items": [
    {"number": 545, "title": "...", "body": "...", "labels": ["enhancement"],
     "state": "OPEN", "is_epic": false, "deps": [544],
     "skip": false, "skip_reason": null, "source_epic": null}
  ],
  "skipped":        [{"number": 541, "reason": "closed"}],
  "epics_expanded": [{"number": 549, "children": [544, 545, 546, 547, 548]}],
  "epics_unwired":  []
}
```

Parse the JSON. **Use `work_items` as the list to act on** for the rest of the swarm — each entry already has everything Steps 2–5 need (title, body, labels, state, deps, and the originating epic when expanded from one).

**Skip announcement** — for each entry in `skipped`, the script has already applied the existing rules (`on-hold` label, `closed` state). If there are skipped issues from a requested epic's children, announce using the existing template:

> `#N` is an epic. Swarming: `#101`, `#102`. Skipped (closed/on-hold): `#103`.

If `work_items` is empty because every requested issue (or every child of a requested epic) was skipped, announce and stop.

**Unwired epics** — for each number in `epics_unwired`, announce with the existing template and proceed with the remaining work items:

> `#N` is labeled `epic` but has no sub-issues wired via the GitHub sub-issue API. Skipping — children must be attached via `gh api .../sub_issues` before swarming.

The legacy `- [ ] #N` body-checklist format is no longer supported; speckit wires child issues via the native sub-issue API (see `plugins/speckit/skills/spec/SKILL.md`).

If the script exits non-zero, stdout will be empty and stderr will carry a human-readable error — surface it and stop.

### 2. Analyze dependencies and grouping

Use the pre-computed `deps` array on each `work_items` entry — the script already prefers GitHub's native `blockedBy` connection (the field `/spec` wires up) and falls back to parsing `Depends on #N` / `Blocked by #N` from the body when native is empty. Do **not** re-grep bodies here.

Build a directed acyclic graph (DAG): each work item is a node; each number in its `deps` array is a directed edge from the dependent to the dependency.

Produce a **topological sort** of the DAG. This sort determines:
- Which issues can spawn in parallel (no incoming edges in this batch = independent)
- Which issues must wait for their dependencies to complete and merge first (dependent chains)

Output two categories:
- **Independent issues**: no dependencies within this batch — spawn in parallel targeting `$BASE`
- **Dependent chains**: ordered by topology — each dependent must wait for its dependency's PR to merge before spawning

- **File conflicts**: issues touching the same files must not share an agent
- **Grouping**: small independent fixes to the same file can share one agent

### 3. Present swarm plan

Show the user a table before launching:

```
| Agent | Issue(s) | Branch | Files affected | Model | Notes |
|-------|----------|--------|----------------|-------|-------|
| 1     | #16      | fix/readme-accuracy | README.md | sonnet | Independent |
| 2     | #18, #19 | chore/clean-hooks   | hooks/check.py | opus | Grouped: same file |
```

> Any agent showing `haiku` must be re-assigned to `sonnet` before proceeding.

Also show suggested merge order and any issues too ambiguous to delegate. Merge order is bottom-up: root PRs first, leaves last (the same order as creation). This matches how `swarmkit:merge-stack` operates — it retargets every non-root PR to `$BASE` up front, then merges each chain from the root upward with a uniform squash.

Present the plan and proceed immediately with the proposed groupings.

**Model selection** (when `--model` not set):

| Complexity | Model |
|------------|-------|
| Mechanical / single-file / well-specified | `sonnet` |
| Multi-file / new components / logic / judgment | `opus` |

### 4. Spawn agents

Before spawning each agent, ensure the `status:in-progress` label exists and apply it to the issue(s) being worked on:

```bash
gh label list | grep -q "status:in-progress" || \
  gh label create "status:in-progress" --description "Actively being worked on" --color "E4E669"

gh issue edit <issue> --add-label "status:in-progress"
```

GitHub will automatically remove `status:in-progress` visibility when the issue closes via the `Closes #N` PR reference — no manual cleanup needed.

Apply the hybrid spawn strategy based on the dependency graph from Step 2:

In epic mode, agents branch from `$EPIC_BRANCH` (which was cut from `origin/main` in the epic-mode resolution step) for their initial worktree, and their PRs target `$EPIC_BRANCH` because `claude.flowkit.prBase` is pinned to it. Stack-root PRs target `$EPIC_BRANCH` instead of `$BASE`; stack-leaf PRs still target their predecessor (which ultimately roots at `$EPIC_BRANCH`).

**Independent issues** (no dependencies within this batch):
- Spawn all in parallel
- Each agent branches from `$BASE` (e.g., `main`, or `$EPIC_BRANCH` when epic mode is on)
- Use `run_in_background: true`

**Dependent chains** (issues with dependencies):
- Spawn sequentially in topological order
- Each agent waits for its dependency's agent to complete and its PR to be created
- The dependent agent branches from its dependency's branch tip (not `$BASE`):
  ```bash
  git fetch origin worktree-agent-<dependency-issue>
  git checkout -b worktree-agent-<this-issue> origin/worktree-agent-<dependency-issue>
  ```
- The dependent agent's PR targets the dependency's branch (not `$BASE`):
  ```bash
  gh pr create --base worktree-agent-<dependency-issue> --head worktree-agent-<this-issue> \
    --title "..." --body "Closes #<this-issue>"
  ```
- When the dependency merges to `$BASE`, GitHub automatically retargets the dependent PR to `$BASE`

> **Why no mid-swarm merge is needed**: by branching from `origin/worktree-agent-<dependency-issue>`, the dependent agent already has full access to every file and commit produced by the upstream agent. The stacked branch strategy exists precisely so that downstream agents can proceed without waiting for a merge — the upstream output is already present in their working tree. Never merge a dependency's PR early to "unblock" a downstream agent.

All agents (both strategies) use:
- `isolation: "worktree"`
- `mode: "bypassPermissions"`
- `run_in_background: true`
- Branch naming: `worktree-agent-<issue>` (required for `clean-worktrees`)
- A deterministic, addressable `name:` parameter: `swarm-builder-<issue>`. This is kept for forward compatibility with a future runtime that supports persistent standby; today it has no functional effect since the harness terminates the builder anyway.

Each agent prompt MUST include:
1. **TASK**: the specific issue(s) to resolve
2. **EXPECTED OUTCOME**: branch name, commit format, PR closing the issue(s)
3. **MUST DO**: concrete file changes from the issue body
4. **MUST NOT DO**: scope boundaries
5. **CONTEXT**: Instruct agents that their CWD is the repo root — use **relative paths only** for all file operations (e.g., `plugins/flowkit/skills/ship/SKILL.md`). Do NOT include the absolute repo path — agents will resolve it into absolute paths that bypass the worktree and edit the main directory instead.

Each agent prompt MUST include these **workflow steps** (in order):

```
1. Create and check out branch from the appropriate base. Use `origin/<base>` as the starting point so this works inside an isolated worktree — a plain `git checkout <base>` would fail if `<base>` is already checked out in the main repo. `<base>` is `main` (or the `feature/<slug>-<N>` epic branch when one was cut) for independent issues and `worktree-agent-<dependency-issue>` for dependent ones.

   git fetch origin <base>
   git checkout -B worktree-agent-<issue> origin/<base>

   # Safety check — abort if not in an isolated worktree
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not running in an isolated worktree. Aborting to prevent branch collision." && exit 1

   # Ancestry sanity — abort if HEAD doesn't descend from origin/<base>. Defends
   # against the post-rebase-merge worktree-base drift bug (#923): EnterWorktree
   # may silently root the worktree on a stale SHA chain even when the checkout
   # targeted the right branch.
   if ! git merge-base --is-ancestor origin/<base> HEAD; then
     echo "ERROR: HEAD is not a descendant of origin/<base>. Worktree may be rooted on a stale base." >&2
     echo "       Run: git fetch origin <base> && git reset --hard origin/<base>" >&2
     exit 1
   fi

2. Make changes (the actual issue work)
3. Stage and commit using conventional-commit-message format:
   - No Claude mentions, no co-author lines
   git add <files> && git commit -m "<type>(<scope>): <description>"
4. Push the branch:
   git push -u origin worktree-agent-<issue>
5. Create PR targeting the appropriate base — `main` (or the pinned `feature/<slug>-<N>` branch via `claude.flowkit.prBase`) for independent issues, `worktree-agent-<dependency-issue>` for dependent ones. The body MUST be a richer summary, not just `Closes #<issue>` — synthesize the `## Summary` bullets from the issue's acceptance criteria and your diff, and describe the `## Test plan` in terms of those acceptance criteria. Fill in the angle-bracket placeholders; do not copy them literally.

   <!-- include: plugins/_shared/pr-body.md -->
   <!-- Summary-content rules derive from the canonical doc; `## Changes` is intentionally omitted for single-issue swarm PRs — Summary is sufficient when the scope is one issue. -->

   gh pr create --base <base> --head worktree-agent-<issue> \
     --title "<type>(<scope>): <description>" \
     --body "$(cat <<'EOF'
   ## Summary
   <1–3 bullets synthesizing what was changed, derived from the issue acceptance criteria and the diff>

   ## Test plan
   <how to verify the changes satisfy the acceptance criteria>

   Closes #<issue>
   EOF
   )"
6. Report the PR URL. This is the ONLY acceptable termination condition for this workflow. Do not stop before the PR exists and its URL has been reported.
```

Append the following STANDBY clause to the end of every builder prompt. **In today's runtime the harness terminates the builder shortly after it emits the final notification, so this clause is effectively a no-op** — but it is left in place so the prompt remains correct if a future runtime preserves agents past their last notification.

> **STANDBY (forward-compat).** After reporting the PR URL, reply `STANDBY_READY` and then enter standby, awaiting an orchestrator SendMessage. If the harness terminates you instead of delivering a message, that is expected under the current runtime. If a message does arrive, it will be one of two:
>
> 1. `"Approved. Terminate."` — exit cleanly.
> 2. A `REVIEWER FINDINGS` payload with explicit scope — apply the in-scope items (blockers, concerns, `[recommended]` coverage gaps), skip the out-of-scope items (nits, `[optional]`), run `<verify_command>` and the relevant test scope, commit (conventional-commit format, no Claude mentions, no co-author lines), `git push origin <head_branch>`, and optionally `gh pr comment <pr_number>` summarizing what was addressed and what was deferred. Then terminate.
>
> All swarm constraints still apply: never branch off `main` for the fix round (you are already on the PR's head branch in your worktree), never force-push, never close the issue manually.

### 5. Handle completions

After each agent completes, run the verify script once per agent:

```bash
"$SKILL_DIR/scripts/verify_agent.sh" <issue>
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{
  "issue": 102,
  "branch": "worktree-agent-102",
  "branch_pushed": true,
  "pushed_now": false,
  "pr_exists": true,
  "pr_url": "https://github.com/owner/name/pull/210",
  "pr_base": "main"
}
```

Parse the JSON and act on the fields:

- **`branch_pushed: false` and no local branch** — the agent produced no push and no local branch exists; announce the unrecoverable failure and treat the issue as failed (do not attempt PR creation).
- **`pushed_now: true`** — the script pushed the branch on the agent's behalf; announce this before proceeding.
- **`pr_exists: false`** — create the PR on the agent's behalf using the agent's commits and the issue spec. PR creation (title, body, base branch selection) is a judgment call made by Claude using the existing PR-body template from Step 4. Use `pr_base` from the preflight JSON (or the appropriate stacked-branch base for dependent issues) as the `--base` argument.
- **`pr_exists: true`** — no action needed; `pr_url` carries the existing PR link.

If the script exits non-zero, stdout will be empty and stderr will carry a human-readable error — surface it and treat the issue as failed.

Report the PR link once confirmed. Verify each PR's diff matches the issue scope.

Record `(issue, pr_number, head_branch, base_branch)` for each confirmed PR — the review/fix pass consumes this list.

### 6. Review/fix pass

Every confirmed PR passes through this pass. Do NOT block on every PR before starting — dispatch a reviewer for each PR as soon as it is confirmed.

**6a. Spawn a reviewer per PR.** Spawn the **`swarmkit:swarm-reviewer`** agent with `run_in_background: true`. Default model `sonnet`; override via `--reviewer-model`.

The reviewer prompt MUST include:

- The PR number, title, and `Closes #<issue>` reference
- The original issue body (for spec / acceptance-criteria comparison)
- An explicit instruction: **return the review inline; do NOT post it as a `gh pr comment`**
- A required output structure:
  - **Verdict**: Approve / Request changes / Comment
  - **Blockers** (must fix)
  - **Concerns** (worth raising, not blocking)
  - **Nits** (style, optional)
  - **Coverage gaps** (with `[recommended]` or `[optional]` tag per gap)

**Verdict delivery contract.** Per the reviewer agent's contract (`plugins/swarmkit/agents/swarm-reviewer.md`), the reviewer `SendMessage`s its complete structured verdict to the parent (this orchestrator) before terminating. The idle notification alone does not carry the verdict text — wait for the `SendMessage` payload to parse the result and apply the skip-on-clean rule. If only an idle notification arrives with no accompanying `SendMessage` payload, treat the reviewer as having returned no output and note the missing review in the final summary.

Track each reviewer's agent ID against the PR it covers.

**6b. Decide whether to spawn a fix-round worker.** When the reviewer's `SendMessage` payload arrives, parse its result and apply the **skip-on-clean** rule:

| Reviewer output | Action |
|-----------------|--------|
| Verdict `Approve` AND no blockers AND no concerns AND no `[recommended]` coverage gaps | No fix-round worker. PR stands as-is. Nits and `[optional]` coverage gaps are not actionable enough to warrant a fix round. |
| Any blockers | Spawn fix-round worker. Blockers are mandatory. |
| Any concerns | Spawn fix-round worker. Concerns get addressed or explicitly deferred in a PR comment. |
| Coverage gaps flagged `[recommended]` | Spawn fix-round worker. Treat recommended coverage gaps as concerns. |

Print one line announcing the decision per PR:

```
PR #1390: reviewer clean (no blockers/concerns) → no fix round
PR #1391: reviewer flagged 1 blocker, 2 concerns → spawning fresh worker
```

**6c. Spawn the fix-round worker.** For every PR whose reviewer verdict was non-clean, spawn a fresh `general-purpose` agent with `isolation: worktree`, `mode: bypassPermissions`, `run_in_background: true`. Default model `sonnet`; override via `--worker-model`.

The fix-round worker prompt MUST:

- Include the **PR number** and **head branch** (e.g. `worktree-agent-42`).
- Include the **full reviewer output** verbatim under a `REVIEWER FINDINGS` section.
- State explicit scope:
  - **In scope**: blockers (mandatory), concerns (address or explicitly defer with stated reason in a PR comment), reviewer-recommended coverage gaps.
  - **Out of scope**: nits (skip unless trivially co-located with a fix), `[optional]` coverage gaps, unrelated cleanups, scope creep.
- Instruct the worker to:
  1. Branch from the **existing PR branch**, NOT from `main`:
     ```bash
     git fetch origin <head_branch>
     git checkout -B <head_branch> origin/<head_branch>
     ```
  2. Apply the changes.
  3. Run `<verify_command>` (resolved in Setup) and the relevant test scope. Resolve any failures before proceeding — never push a red build.
  4. Commit with conventional-commit format (no Claude mentions, no co-author lines).
  5. Push to the same branch (`git push origin <head_branch>`) — auto-updates the PR.
  6. Optionally comment on the PR summarizing what was addressed and what was deferred:
     ```bash
     gh pr comment <pr_number> --body "Addressed reviewer feedback: <summary>. Deferred: <items with reasons>."
     ```
- Forbid: branching off `main`, force-pushing, rewriting prior commits, closing the issue manually.
- Termination: report the new commit SHAs and confirm `gh pr view <pr_number> --json commits` includes them.

**6d. Wait for all fix-round workers.** Continue until every spawned fix-round worker reports completion. Verify the PR's HEAD has advanced:

```bash
gh pr view <pr_number> --json commits | jq '.commits[-1].oid'
```

For PRs with no fix round (clean reviewer verdict), no further action is needed.

**Review/fix-pass failure modes:**

| Symptom | Handling |
|---------|----------|
| Swarm agent fails to produce a PR | Skip review/fix round for that issue; report in final summary |
| Reviewer crashes or returns no output | Note the missing review in the final summary; leave PR open without a fix pass |
| Fix-round worker push rejected (branch advanced underneath) | Worker re-fetches and rebases (`git fetch origin <head>; git rebase origin/<head>`); if conflicts arise, abort and report to user |
| Fix-round worker introduces new test failures | Worker MUST resolve before push — never push a red build |

### 7. Clean up

Run `/clean-worktrees` to remove agent worktrees and orphaned branches. This frees local `worktree-agent-*` branches so the merge step can use `--delete-branch` without conflicts.

Then run `scripts/teardown.sh` to clear the `claude.flowkit.prBase` pin set during Setup. Leaving it set would cause subsequent PR creation (even in unrelated workflows) to target the wrong base, so this clearance is critical. Mirror the Loop-Mode teardown invocation pattern — in epic mode pass `--keep-pr-base` so the epic branch and pin survive for the final epic-to-`main` ship step; off epic mode, unset unconditionally:

```bash
if [ "$EPIC_MODE" = "on" ]; then
  "$SKILL_DIR/scripts/teardown.sh" --base "$BASE" --keep-pr-base
else
  "$SKILL_DIR/scripts/teardown.sh" --base "$BASE"
fi
```

Parse the returned JSON and confirm `base_restored: true`. If `config_unset: false` and `config_kept_for_epic` is absent, the pin was already clear — this is not a failure. When `config_kept_for_epic: true` appears, the pin is intentionally preserved for the ship-epic step; announce the same epic-handoff guidance as Loop Mode's Teardown.

### 8. Report

```
| Issue(s) | PR | Branch | Status |
|----------|-----|--------|--------|
| #16      | #25 | fix/readme-accuracy | Open |
| #18, #19 | #26 | chore/clean-hooks   | Open |
```

All PRs are left open for review. If 1 PR open: use `/merge-pr` to merge it. If 2+ PRs: use `/merge-stack` — retargets non-root PRs to the stack root's base and merges bottom-up: root PRs first, leaves last. In epic mode, after all child PRs are merged into the epic branch via `/merge-stack`, open a single PR from the epic branch to `main` and squash-merge it (verify the integrated state first); then unset `claude.flowkit.prBase` and delete the epic branch.

---

## Loop Mode

Used when no issue numbers are given (no args or label filter). Continuously clears the board.

### Setup

Run the preflight script with `--scope-pr-base` to also set `claude.flowkit.prBase` for this session:

```bash
"$SKILL_DIR/scripts/preflight.sh" --base "$BASE" --scope-pr-base
```

Parse the JSON from stdout. Halt and surface stderr if the script exits non-zero or if `gh_authenticated` is `false`. Announce base creation if `base_created` is `true`.

`claude.flowkit.prBase` is unset in the teardown step below. Leaving it set will cause subsequent PR creation (even in unrelated workflows) to target the wrong base, so cleanup is critical.

### Loop (repeat until board clear or user stops)

**Step 1 — Pick batch**

Follow `gh-fetch-issues` to fetch open issues (apply label filter if given), then follow `issue-rank` to rank and select all issues that can safely parallelize this cycle:
- No two issues touch the same files
- No unresolved dependencies within the batch
- Present the batch in the standard next-issue table format; note any deferred issues and why

If no open issues remain, announce "Board is clear" and fall through to the Teardown section (do not `exit` here — the pin must be cleared first).

**Step 2 — Swarm**

Run the one-shot swarm flow above on the batch. Independent issues target `$BASE` (enforced by `claude.flowkit.prBase`). Dependent issues target their dependency's branch, forming a stacked-PR chain that ultimately merges into `$BASE` when `swarmkit:merge-stack` cascades the merges.

**Step 3 — Checkpoint**

```
── Cycle N complete ──────────────────────────
✓ PRs opened: #25 (→ #12), #26 (→ #15)
✗ Failed: #14 (agent crash, no PR produced)
⊘ Blocked: #20 (depends on #14)
⧖ Remaining open issues: 5
──────────────────────────────────────────────
```

Proceed immediately to the next cycle after printing the checkpoint summary. The loop halts only on unrecoverable failures: an agent crash with no PR produced. When the loop halts for any reason — board clear, user stop, or unrecoverable failure — it MUST fall through to the Teardown section below before terminating. Never `exit` directly from inside the loop; the Teardown is the single exit funnel that clears the pin.

### Teardown

1. Run the `clean-worktrees` skill
2. Run `scripts/teardown.sh` with the appropriate flags:

```bash
if [ "$EPIC_MODE" = "on" ]; then
  "$SKILL_DIR/scripts/teardown.sh" --base "$BASE" --keep-pr-base
else
  "$SKILL_DIR/scripts/teardown.sh" --base "$BASE"
fi
```

Parse the returned JSON and confirm `base_restored: true`. If `config_unset: false` and `config_kept_for_epic` is absent, log that `claude.flowkit.prBase` was already clear — this is not a failure.

When `config_kept_for_epic: true` appears in the JSON, announce:

> Epic branch `<EPIC_BRANCH>` is left in place with `claude.flowkit.prBase` pinned. After all child PRs land via `/merge-stack`, open a final PR from `<EPIC_BRANCH>` to `main` and squash-merge it; then unset `claude.flowkit.prBase` and delete the epic branch.

Optionally, run `swarmkit:clean-remote-worktrees` afterwards to sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs. This is not automatic — invoke it when you want to tidy up.

3. Final summary:

```
── swarm complete ────────────────────────────
Cycles: 3
Issues addressed: #12, #14, #15 (PRs open, awaiting review)
Issues remaining: #25
Open PRs: #31, #32, #33

Open PRs are ready for review. If 1 PR open: use `/merge-pr` to merge it. If 2+ PRs: use `/merge-stack` — retargets non-root PRs to the stack root's base and merges bottom-up: root PRs first, leaves last.
In epic mode: after /merge-stack fans child PRs into the epic branch, open a final epic-to-main PR, squash-merge it, then unset `claude.flowkit.prBase` and delete the epic branch.
─────────────────────────────────────────────
```

### Smart failure rules

When an issue fails at any point:
1. Check all remaining issues in current and future cycles for file overlap or explicit references to the failed issue
2. Mark those as blocked; continue with all unblocked issues
3. Report blocked issues at each checkpoint

**Unrecoverable failures** (halt the loop, then run Teardown before terminating):
- Agent produced no PR (crash, timeout, no push)
- `$BASE` branch deleted or corrupted externally

Even on an unrecoverable failure, the loop does not exit in place — it breaks out of the cycle and proceeds to the Teardown section so `scripts/teardown.sh` always runs and the `claude.flowkit.prBase` pin is cleared (or preserved via `--keep-pr-base` in epic mode). This is the trap/finally equivalent: there is no early-exit path that bypasses teardown.
