---
name: swarm-experimental
description: EXPERIMENTAL variant of `/swarm` that collapses preflight into a single scripted step. Same arg grammar and behavior — see `/swarm` for the stable version. Use this to dogfood script-extraction changes; switch back to `/swarm` if anything misbehaves.
---

# Swarm Skill (Experimental)

> **EXPERIMENTAL** — this is a parallel build of `/swarm` used to validate script extractions that reduce conversational bash round-trips. Behavior is intended to be identical to the stable `/swarm` skill on the same inputs. If you hit issues, fall back to `/swarm`.

> See the swarmkit README's [Permissions](../../README.md#permissions) section for session-level permission guidance before first use.

Spawn parallel agents for GitHub issues: $ARGUMENTS

## Arguments

Parse `$ARGUMENTS` to determine the mode:

- **No arguments** → **loop mode**, all open issues → `develop`
- **Label text** (non-numeric, e.g. `bug`, `priority:high`) → **loop mode**, filtered by label → `develop`
- **Issue numbers** (`12 15 18`, `#12 #15 #18`, range `12-18`) → **one-shot mode**, specific issues → `develop`
- `--model <tier>` (`sonnet`, `opus`) → model override for all agents
- `--base <branch>` → override default base branch

---

## Setup

Run the preflight script once. It handles fetch, base-branch verification (creating it from `main` and pushing if missing), and `gh` auth check in a single call:

```bash
plugins/swarmkit/skills/swarm-experimental/scripts/preflight.sh --base "$BASE"
```

On success the script exits 0 and emits a single JSON object on stdout:

```json
{"base": "develop", "base_existed": true, "base_created": false, "gh_authenticated": true, "repo": "owner/name"}
```

Parse the JSON. If `gh_authenticated` is `false`, **stop immediately** and surface the script's stderr to the user — no swarm work can proceed without `gh` auth. If `base_created` is `true`, announce:

> Created `<base>` branch from `main`. All PRs will target `<base>`.

If the script exits non-zero, stdout will be empty and stderr will carry a human-readable error — surface it and stop.

---

## One-Shot Mode

Used when issue numbers are provided. Dispatches agents for the given set of issues, opens PRs, and reports. Use `swarmkit:merge-stack` to merge.

### 1. Gather issue details

Run the gather script once with all requested issue numbers. It batches title, body, labels, state, sub-issues, and native dependency edges (`blockedBy`) into a single `gh api graphql` call, collapsing what was ~3N bash turns into one script invocation:

```bash
plugins/swarmkit/skills/swarm-experimental/scripts/gather_issues.sh <number> [<number> ...]
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

Also show suggested merge order and any issues too ambiguous to delegate. Merge order is top-down: leaf PRs first, root last (the inverse of creation order). This matches how `swarmkit:merge-stack` operates — it pops the leaf of the stack first.

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

**Independent issues** (no dependencies within this batch):
- Spawn all in parallel
- Each agent branches from `$BASE` (e.g., `develop`)
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

Each agent prompt MUST include:
1. **TASK**: the specific issue(s) to resolve
2. **EXPECTED OUTCOME**: branch name, commit format, PR closing the issue(s)
3. **MUST DO**: concrete file changes from the issue body
4. **MUST NOT DO**: scope boundaries
5. **CONTEXT**: Instruct agents that their CWD is the repo root — use **relative paths only** for all file operations (e.g., `plugins/flowkit/skills/release/SKILL.md`). Do NOT include the absolute repo path — agents will resolve it into absolute paths that bypass the worktree and edit the main directory instead.

Each agent prompt MUST include these **workflow steps** (in order):

```
1. Create and check out branch from the appropriate base. Use `origin/<base>` as the starting point so this works inside an isolated worktree — a plain `git checkout develop` would fail if `develop` is already checked out in the main repo.
   # For independent issues (no deps in this batch):
   git fetch origin develop
   git checkout -B worktree-agent-<issue> origin/develop

   # For dependent issues (has a dependency in this batch):
   git fetch origin worktree-agent-<dependency-issue>
   git checkout -B worktree-agent-<issue> origin/worktree-agent-<dependency-issue>

   # Safety check — abort if not in an isolated worktree
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not running in an isolated worktree. Aborting to prevent branch collision." && exit 1

2. Make changes (the actual issue work)
3. Stage and commit using conventional-commit-message format:
   - No Claude mentions, no co-author lines
   git add <files> && git commit -m "<type>(<scope>): <description>"
4. Push the branch:
   git push -u origin worktree-agent-<issue>
5. Create PR targeting the appropriate base. The body MUST be a richer summary, not just `Closes #<issue>` — synthesize the `## Summary` bullets from the issue's acceptance criteria and your diff, and describe the `## Test plan` in terms of those acceptance criteria. Fill in the angle-bracket placeholders; do not copy them literally.

   <!-- include: plugins/_shared/pr-body.md -->
   <!-- Summary-content rules derive from the canonical doc; `## Changes` is intentionally omitted for single-issue swarm PRs — Summary is sufficient when the scope is one issue. -->

   # For independent issues:
   gh pr create --base develop --head worktree-agent-<issue> \
     --title "<type>(<scope>): <description>" \
     --body "$(cat <<'EOF'
   ## Summary
   <1–3 bullets synthesizing what was changed, derived from the issue acceptance criteria and the diff>

   ## Test plan
   <how to verify the changes satisfy the acceptance criteria>

   Closes #<issue>
   EOF
   )"

   # For dependent issues:
   gh pr create --base worktree-agent-<dependency-issue> --head worktree-agent-<issue> \
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

### 5. Handle completions

After each agent completes, run the verify script once per agent:

```bash
plugins/swarmkit/skills/swarm-experimental/scripts/verify_agent.sh <issue>
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
  "pr_base": "develop"
}
```

Parse the JSON and act on the fields:

- **`branch_pushed: false` and no local branch** — the agent produced no push and no local branch exists; announce the unrecoverable failure and treat the issue as failed (do not attempt PR creation).
- **`pushed_now: true`** — the script pushed the branch on the agent's behalf; announce this before proceeding.
- **`pr_exists: false`** — create the PR on the agent's behalf using the agent's commits and the issue spec. PR creation (title, body, base branch selection) is a judgment call made by Claude using the existing PR-body template from Step 4. Use `pr_base` from the preflight JSON (or the appropriate stacked-branch base for dependent issues) as the `--base` argument.
- **`pr_exists: true`** — no action needed; `pr_url` carries the existing PR link.

If the script exits non-zero, stdout will be empty and stderr will carry a human-readable error — surface it and treat the issue as failed.

Report the PR link once confirmed. Verify each PR's diff matches the issue scope.

### 6. Clean up

Run `/clean-worktrees` to remove agent worktrees and orphaned branches. This frees local `worktree-agent-*` branches so the merge step can use `--delete-branch` without conflicts.

### 7. Report

```
| Issue(s) | PR | Branch | Status |
|----------|-----|--------|--------|
| #16      | #25 | fix/readme-accuracy | Open |
| #18, #19 | #26 | chore/clean-hooks   | Open |
```

All PRs are left open for review. If 1 PR open: use `/merge-pr` to merge it into `develop`. If 2+ PRs: use `/merge-stack` — merges top-down: leaf PRs first, root last.

---

## Loop Mode

Used when no issue numbers are given (no args or label filter). Continuously clears the board.

### Setup

Run the preflight script with `--scope-pr-base` to also set `claude.flowkit.prBase` for this session:

```bash
plugins/swarmkit/skills/swarm-experimental/scripts/preflight.sh --base "$BASE" --scope-pr-base
```

Parse the JSON from stdout. Halt and surface stderr if the script exits non-zero or if `gh_authenticated` is `false`. Announce base creation if `base_created` is `true`.

`claude.flowkit.prBase` is unset in the teardown step below. Leaving it set will cause subsequent PR creation (even in unrelated workflows) to target the wrong base, so cleanup is critical.

### Loop (repeat until board clear or user stops)

**Step 1 — Pick batch**

Follow `gh-fetch-issues` to fetch open issues (apply label filter if given), then follow `issue-rank` to rank and select all issues that can safely parallelize this cycle:
- No two issues touch the same files
- No unresolved dependencies within the batch
- Present the batch in the standard next-issue table format; note any deferred issues and why

If no open issues remain, announce "Board is clear" and exit.

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

Proceed immediately to the next cycle after printing the checkpoint summary. The loop halts only on unrecoverable failures: an agent crash with no PR produced.

### Teardown

1. Run the `clean-worktrees` skill
2. Run `scripts/teardown.sh` (optionally `--base <branch>` to override the default `develop`). Parse the returned JSON and confirm `base_restored: true`. If `config_unset: false`, log that `claude.flowkit.prBase` was already clear — this is not a failure.

Optionally, run `swarmkit:clean-remote-worktrees` afterwards to sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs. This is not automatic — invoke it when you want to tidy up.

3. Final summary:

```
── swarm complete ────────────────────────────
Cycles: 3
Issues addressed: #12, #14, #15 (PRs open, awaiting review)
Issues remaining: #25
Open PRs: #31, #32, #33

Open PRs are ready for review. If 1 PR open: use `/merge-pr` to merge it into `$BASE`. If 2+ PRs: use `/merge-stack` — merges top-down: leaf PRs first, root last.
─────────────────────────────────────────────
```

### Smart failure rules

When an issue fails at any point:
1. Check all remaining issues in current and future cycles for file overlap or explicit references to the failed issue
2. Mark those as blocked; continue with all unblocked issues
3. Report blocked issues at each checkpoint

**Unrecoverable failures** (exit loop immediately):
- Agent produced no PR (crash, timeout, no push)
- `$BASE` branch deleted or corrupted externally

---

## Constraints

- Never merge into `main` — all PRs ultimately merge into `$BASE`; stacked (dependent) PRs may target an intermediate dependency branch and cascade into `$BASE` via `swarmkit:merge-stack`
- Never pause between loop cycles — proceed immediately after printing the checkpoint summary
- Never skip a failed issue's dependents — always analyze and block them
- Every agent must work in an isolated worktree
- Every PR must reference the issue it closes (`Closes #N`)
- Commit messages must follow `conventional-commit-message` sub-skill format
- Never mention Claude or add co-author lines in commit messages
- Agents spawn with `mode: "bypassPermissions"` so they can push and create PRs without prompting
- Never commit directly to develop or main — always work on the `worktree-agent-<issue>` branch
- **Never close issues** — issues are closed by the release process when staging merges to main
- **Never pass absolute repo paths to spawned agents** — always instruct them to use relative paths from their CWD to ensure edits land in the isolated worktree, not the main directory
- **Never merge a PR mid-swarm**, even when a downstream agent needs files produced by an upstream agent. Dependent agents branch from `origin/worktree-agent-<dependency>` and already have access to the upstream output. Merging to unblock a downstream agent bypasses the user's review gate and is never acceptable.
