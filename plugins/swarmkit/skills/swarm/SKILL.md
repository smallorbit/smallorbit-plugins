---
name: swarm
description: Spawn parallel isolated-worktree agents for GitHub issues, open stacked PRs in dependency order, and leave them open for review. Use `swarmkit:merge-stack` to merge. Supports one-shot mode (specific issue numbers) and loop mode (clear the board continuously).
---

# Swarm Skill

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

Before entering either mode, ensure `develop` exists. This runs unconditionally.

```bash
git fetch origin
```

Check if `develop` exists on remote:

```bash
git ls-remote --exit-code origin develop
```

If it does **not** exist, create it from `main` and announce it:

```bash
git checkout main
git pull origin main
git checkout -b develop
git push -u origin develop
```

> Created `develop` branch from `main`. All PRs will target `develop`.

If `develop` already exists, do nothing — proceed.

---

## One-Shot Mode

Used when issue numbers are provided. Dispatches agents for the given set of issues, opens PRs, and reports. Use `swarmkit:merge-stack` to merge.

### 1. Gather issue details

For each issue:

```bash
gh issue view <number> --json title,body,labels
```

**Skip any issue with the `on-hold` label** — per the `gh-fetch-issues` sub-skill filtering rules.

**Epic expansion** — for each issue, query its children via GitHub's native sub-issue relationship:

```bash
gh api repos/{owner}/{repo}/issues/<number>/sub_issues
```

If the response is a non-empty array, the issue is an epic. Use the returned children (not the epic itself) as the work items: for each child, fetch `title,body,labels,state` in parallel, then filter:

- Skip any child with the `on-hold` label
- Skip any child that is already `closed`

If all children are skipped, announce and stop. Otherwise announce:

> `#N` is an epic. Swarming: `#101`, `#102`. Skipped (closed/on-hold): `#103`.

**Epic label without sub-issues** — if the issue carries the `epic` label but the sub-issues API returns an empty array, the epic is not wired up. Do **not** fall through and treat it as a regular implementation issue — the epic body is a plan, not a spec. Announce and skip:

> `#N` is labeled `epic` but has no sub-issues wired via the GitHub sub-issue API. Skipping — children must be attached via `gh api .../sub_issues` before swarming.

The legacy `- [ ] #N` body-checklist format is no longer supported; speckit wires child issues via the native sub-issue API (see `plugins/speckit/skills/spec/SKILL.md`).

### 2. Analyze dependencies and grouping

**Parse the dependency graph** from the issue bodies already fetched in Step 1:

For each issue body, extract `Depends on #N` and `Blocked by #N` references:

```bash
echo "$BODY" | grep -oiE '(depends on|blocked by) #[0-9]+' | grep -oE '[0-9]+'
```

Build a directed acyclic graph (DAG): each issue is a node; a `Depends on #N` or `Blocked by #N` relationship is a directed edge from the dependent to the dependency.

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
5. **SELF-REVIEW**: follow `self-review` sub-skill before creating PR
6. **CONTEXT**: Instruct agents that their CWD is the repo root — use **relative paths only** for all file operations (e.g., `plugins/flowkit/skills/release/SKILL.md`). Do NOT include the absolute repo path — agents will resolve it into absolute paths that bypass the worktree and edit the main directory instead.

Each agent prompt MUST include these **workflow steps** (in order):

```
1. Create and check out branch from the appropriate base:
   # For independent issues (no deps in this batch):
   git checkout develop && git pull origin develop
   git checkout -b worktree-agent-<issue>

   # For dependent issues (has a dependency in this batch):
   git fetch origin worktree-agent-<dependency-issue>
   git checkout -b worktree-agent-<issue> origin/worktree-agent-<dependency-issue>

   # Safety check — abort if not in an isolated worktree
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not running in an isolated worktree. Aborting to prevent branch collision." && exit 1

2. Make changes (the actual issue work)
3. Stage and commit using conventional-commit-message format:
   - No Claude mentions, no co-author lines
   git add <files> && git commit -m "<type>(<scope>): <description>"
4. Push the branch:
   git push -u origin worktree-agent-<issue>
5. Create PR targeting the appropriate base. The body MUST be a richer summary, not just `Closes #<issue>` — synthesize the `## Summary` bullets from the issue's acceptance criteria and your diff, and describe the `## Test plan` in terms of those acceptance criteria. Fill in the angle-bracket placeholders; do not copy them literally.
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
```

### 5. Handle completions

- If agent pushed and created a PR: report the PR link
- If agent was blocked on push (sandbox): push the branch and create PR on its behalf
- Verify each PR's diff matches the issue scope

### 6. Clean up

Run `/clean-worktrees` to remove agent worktrees and orphaned branches. This frees local `worktree-agent-*` branches so the merge step can use `--delete-branch` without conflicts.

### 7. Report

```
| Issue(s) | PR | Branch | Status |
|----------|-----|--------|--------|
| #16      | #25 | fix/readme-accuracy | Open |
| #18, #19 | #26 | chore/clean-hooks   | Open |
```

All PRs are left open for review. If 1 PR open: use `/merge-pr` to land it into `develop`. If 2+ PRs: use `/merge-stack` — merges top-down: leaf PRs first, root last.

---

## Loop Mode

Used when no issue numbers are given (no args or label filter). Continuously clears the board.

### Setup

```bash
git fetch origin
```

Set `claude.flowkit.prBase` to scope the PR base for this operation:

```bash
git config --local claude.flowkit.prBase $BASE
```

This is unset in the teardown step below. Leaving it set will cause subsequent PR creation (even in unrelated workflows) to target the wrong base, so cleanup is critical.

### Loop (repeat until board clear or user stops)

**Step 1 — Pick batch**

Follow `gh-fetch-issues` to fetch open issues (apply label filter if given), then follow `issue-rank` to rank and select all issues that can safely parallelize this cycle:
- No two issues touch the same files
- No unresolved dependencies within the batch
- Present the batch in the standard pick-issue table format; note any deferred issues and why

If no open issues remain, announce "Board is clear" and exit.

**Step 2 — Swarm**

Run the one-shot swarm flow above on the batch. Independent issues target `$BASE` (enforced by `claude.flowkit.prBase`). Dependent issues target their dependency's branch, forming a stacked-PR chain that ultimately lands in `$BASE` when `swarmkit:merge-stack` cascades the merges.

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
2. Restore the base branch (worktree removal may drift the shell to a detached HEAD or a different branch):
   ```bash
   git checkout $BASE && git pull origin $BASE
   ```
3. Unset `claude.flowkit.prBase` to clear the scoped PR base:
   ```bash
   git config --local --unset claude.flowkit.prBase
   ```
3. Final summary:

```
── swarm complete ────────────────────────────
Cycles: 3
Issues addressed: #12, #14, #15 (PRs open, awaiting review)
Issues remaining: #25
Open PRs: #31, #32, #33

Open PRs are ready for review. If 1 PR open: use `/merge-pr` to land it into `$BASE`. If 2+ PRs: use `/merge-stack` — merges top-down: leaf PRs first, root last.
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

- Never merge into `main` — all PRs ultimately land in `$BASE`; stacked (dependent) PRs may target an intermediate dependency branch and cascade into `$BASE` via `swarmkit:merge-stack`
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
