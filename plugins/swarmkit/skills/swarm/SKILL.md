---
name: swarm
description: Spawn parallel isolated-worktree agents for GitHub issues, open stacked PRs in dependency order, and leave them open for review. Use `swarmkit:merge-stack` to merge. Supports one-shot mode (specific issue numbers) and loop mode (clear the board continuously).
---

# Swarm Skill

> See the swarmkit README's [Permissions](../../README.md#permissions) section for session-level permission guidance before first use.

Spawn parallel agents for GitHub issues: $ARGUMENTS

## Arguments

Parse `$ARGUMENTS` to determine the mode:

- **No arguments** → **loop mode**, all open issues → `develop`
- **Label text** (non-numeric, e.g. `bug`, `priority:high`) → **loop mode**, filtered by label → `develop`
- **Issue numbers** (`12 15 18`, `#12 #15 #18`, range `12-18`) → **one-shot mode**, specific issues → `develop`
- `--model <tier>` (`sonnet`, `opus`) → model override for all agents
- `--base <branch>` → override default base branch
- `--no-epic` → suppress feature-branch mode for this run; PRs target `$BASE` directly
- `--epic <slug>` → explicit slug for the auto-cut epic branch (verbatim; `flowkit:cut-epic` enforces the `feature/` prefix)

**Default behavior — feature-branch mode.** When the run will spawn ≥2 agents (any of: 2+ issue numbers, label filter, or loop mode), swarm cuts a `feature/<slug>-<N>` branch via `flowkit:cut-epic`, pins `claude.flowkit.prBase` to it, and routes every spawned PR to that branch. Single-issue one-shot runs are flat-to-`$BASE` (unchanged). Pass `--no-epic` to suppress the cut for a multi-issue run, or `--base <branch>` to override targeting entirely (which also suppresses the cut).

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

**Resolve the slug** (in order):

1. `--epic <slug>` arg → pass verbatim to `flowkit:cut-epic` (`cut-epic` enforces the `feature/` prefix).
2. One-shot multi-issue → pass the lowest issue number to `cut-epic`; it resolves the slug from the issue title via `gh issue view`.
3. Loop mode (no issues, no label) → pass `feature/swarm-$(date +%Y-%m-%d)` as the full branch name (cut-epic accepts the `feature/…` input shape directly).
4. Loop mode + label → pass `feature/<label>-$(date +%Y-%m-%d)` as the full branch name.

**Empty-board edge case (loop mode only)**: defer the cut-epic invocation until the first cycle that selects ≥1 issue. If the board is clear at loop entry, announce "Board is clear" and exit without cutting any branch.

**Cross-pin defensive guard**: before invoking `cut-epic`, read `claude.flowkit.prBase`. If it is set AND starts with `feature/` AND the value differs from the branch about to be cut, exit with:

> `swarm: an epic is already pinned (\`<existing>\`); pass \`--no-epic\` to swarm against develop, or \`--epic <existing-slug>\` to reuse the pinned branch.`

**Invoke `flowkit:cut-epic`** via the Skill tool: `Skill("flowkit:cut-epic", "<resolved-arg>")`. `cut-epic` is idempotent — if the branch already exists locally or on origin it is reused and the pin is refreshed. Capture `EPIC_BRANCH` from cut-epic's report output (the resolved branch name, e.g. `feature/report-serializer-101`).

### When EPIC_MODE=off

Skip the cut. `EPIC_BRANCH` is unset; PRs target `$BASE` directly. Behavior is identical to today's flat-to-`$BASE` flow.

---

## Setup

**Resolve the skill base directory first.** This skill ships with extracted scripts under `scripts/`. When swarmkit is installed via the plugin marketplace, those scripts live in the plugin cache directory — they are **not** at `plugins/swarmkit/skills/swarm/scripts/` relative to the consumer repo's CWD. Before invoking any script, capture the runtime-resolved absolute path that the harness emits in this skill's header (the line `Base directory for this skill: <absolute path>`) into a shell variable:

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
```

Use `"$SKILL_DIR/scripts/..."` for every script invocation below. Do **not** hardcode `plugins/swarmkit/...` — that path only resolves in repos that vendor swarmkit directly.

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

In epic mode, agents still branch from `origin/$BASE` (e.g. `origin/develop`) for their initial worktree, but their PRs target `$EPIC_BRANCH` because `claude.flowkit.prBase` is pinned to it. Stack-root PRs target `$EPIC_BRANCH` instead of `$BASE`; stack-leaf PRs still target their predecessor (which ultimately roots at `$EPIC_BRANCH`).

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

All PRs are left open for review. If 1 PR open: use `/merge-pr` to merge it. If 2+ PRs: use `/merge-stack` — retargets non-root PRs to the stack root's base and merges bottom-up: root PRs first, leaves last. In epic mode, after all child PRs are merged into the epic branch via `/merge-stack`, run `/ship-epic` to rebase-merge the epic branch onto `develop`, clear the pin, and delete the epic branch.

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

> Epic branch `<EPIC_BRANCH>` is left in place with `claude.flowkit.prBase` pinned. Run `/ship-epic` to promote it to `develop` and clear the pin.

Optionally, run `swarmkit:clean-remote-worktrees` afterwards to sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs. This is not automatic — invoke it when you want to tidy up.

3. Final summary:

```
── swarm complete ────────────────────────────
Cycles: 3
Issues addressed: #12, #14, #15 (PRs open, awaiting review)
Issues remaining: #25
Open PRs: #31, #32, #33

Open PRs are ready for review. If 1 PR open: use `/merge-pr` to merge it. If 2+ PRs: use `/merge-stack` — retargets non-root PRs to the stack root's base and merges bottom-up: root PRs first, leaves last.
In epic mode: after /merge-stack fans child PRs into the epic branch, run /ship-epic to promote the epic to develop and clear the pin.
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
- **Never close issues** — issues are closed by the release process when the release merges to main
- **Never pass absolute repo paths to spawned agents** — always instruct them to use relative paths from their CWD to ensure edits land in the isolated worktree, not the main directory
- **Never merge a PR mid-swarm**, even when a downstream agent needs files produced by an upstream agent. Dependent agents branch from `origin/worktree-agent-<dependency>` and already have access to the upstream output. Merging to unblock a downstream agent bypasses the user's review gate and is never acceptable.
