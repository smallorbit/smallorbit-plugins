---
name: swarm
description: Spawn parallel isolated-worktree agents to resolve GitHub issues, open PRs targeting develop, and merge them in dependency order. Supports one-shot mode (specific issue numbers) and loop mode (clear the board continuously).
disable-model-invocation: true
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

Used when issue numbers are provided. Dispatches agents for the given set of issues, merges their PRs, and reports.

### 1. Gather issue details

For each issue:

```bash
gh issue view <number> --json title,body,labels
```

**Skip any issue with the `on-hold` label** — per the `gh-fetch-issues` sub-skill filtering rules.

**Epic expansion** — if the issue body contains a checklist of child issue links in the format `- [ ] #N` or `- [x] #N`, it is an epic. Expand it: extract only unchecked (`- [ ] #N`) child issue numbers, fetch all in parallel, and swarm on the children instead of the epic itself. Skip any child that has the `on-hold` label or is already closed. If all children are skipped, announce and stop. Otherwise announce:

> `#N` is an epic. Swarming: `#101`, `#102`. Skipped (closed/on-hold): `#103`.

### 2. Analyze dependencies and grouping

- **File conflicts**: issues touching the same files must not share an agent
- **Grouping**: small independent fixes to the same file can share one agent
- **Dependency order**: if B depends on A's output, note this for merge ordering

### 3. Present swarm plan

Show the user a table before launching:

```
| Agent | Issue(s) | Branch | Files affected | Model | Notes |
|-------|----------|--------|----------------|-------|-------|
| 1     | #16      | fix/readme-accuracy | README.md | sonnet | Independent |
| 2     | #18, #19 | chore/clean-hooks   | hooks/check.py | opus | Grouped: same file |
```

> Any agent showing `haiku` must be re-assigned to `sonnet` before proceeding.

Also show suggested merge order and any issues too ambiguous to delegate.

Present the plan and proceed immediately with the proposed groupings.

**Model selection** (when `--model` not set):

| Complexity | Model |
|------------|-------|
| Mechanical / single-file / well-specified | `sonnet` |
| Multi-file / new components / logic / judgment | `opus` |

### 4. Spawn agents

Launch all agents in parallel:
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
6. **CONTEXT**: repo path, relevant patterns to follow

Each agent prompt MUST include these **workflow steps** (in order):

```
1. Create and check out branch from develop:
   git checkout develop && git pull origin develop
   git checkout -b worktree-agent-<issue>

   # Safety check — abort if not in an isolated worktree
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not running in an isolated worktree. Aborting to prevent branch collision." && exit 1

2. Make changes (the actual issue work)
3. Stage and commit using conventional-commit-message format:
   - No Claude mentions, no co-author lines
   git add <files> && git commit -m "<type>(<scope>): <description>"
4. Push the branch:
   git push -u origin worktree-agent-<issue>
5. Create PR targeting develop:
   gh pr create --base develop --head worktree-agent-<issue> \
     --title "<type>(<scope>): <description>" \
     --body "Closes #<issue>"
```

### 5. Handle completions

- If agent pushed and created a PR: report the PR link
- If agent was blocked on push (sandbox): push the branch and create PR on its behalf
- Verify each PR's diff matches the issue scope

### 6. Clean up

Run `/clean-worktrees` to remove agent worktrees and orphaned branches. This frees local `worktree-agent-*` branches so the merge step can use `--delete-branch` without conflicts.

### 7. Merge PRs

Merge each PR in the recommended dependency order — for each: `gh pr merge <number> --squash --delete-branch`. After each successful merge, follow the `gh-label-merged-issues` sub-skill on the merged PR number.

If a merge fails:
- Analyze which remaining PRs depend on the failed one
- Merge all independent PRs
- Mark dependents as blocked; leave those PRs open
- Report clearly: which issue failed, why, which are blocked

### 8. Sync develop

Pull the merged changes onto local develop:

```bash
git checkout develop
git pull origin develop
```

### 9. Report

```
| Issue(s) | PR | Branch | Status |
|----------|-----|--------|--------|
| #16      | #25 | fix/readme-accuracy | Merged |
| #18, #19 | #26 | chore/clean-hooks   | Merged |
```

---

## Loop Mode

Used when no issue numbers are given (no args or label filter). Continuously clears the board.

### Setup

```bash
git fetch origin
```

Set `claude.prBase` to scope the PR base for this operation:

```bash
git config --local claude.prBase $BASE
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

Run the one-shot swarm flow above on the batch. Every agent's PR targets `$BASE` (enforced by `claude.prBase`).

**Step 3 — Pull base**

```bash
git checkout $BASE
git pull origin $BASE
```

**Step 4 — Checkpoint**

```
── Cycle N complete ──────────────────────────
✓ Merged: #12, #15
✗ Failed: #14 (merge conflict)
⊘ Blocked: #20 (depends on #14)
⧖ Remaining open issues: 5
──────────────────────────────────────────────
```

Proceed immediately to the next cycle after printing the checkpoint summary. The loop halts only on unrecoverable failures: merge conflict on `$BASE`, agent crash with no PR produced, or push rejected on `$BASE`.

### Teardown

1. Run the `clean-worktrees` skill
2. Restore the base branch (worktree removal may drift the shell to a detached HEAD or a different branch):
   ```bash
   git checkout $BASE && git pull origin $BASE
   ```
3. Unset `claude.prBase` to clear the scoped PR base:
   ```bash
   git config --local --unset claude.prBase
   ```
3. Final summary:

```
── swarm complete ────────────────────────────
Cycles: 3
Issues addressed: #12, #14, #15 (will close when released to main)
Issues remaining: #25
PRs on develop: #31, #32, #33

develop is ready for testing. Cut a release candidate when ready.
─────────────────────────────────────────────
```

### Smart failure rules

When an issue fails at any point:
1. Check all remaining issues in current and future cycles for file overlap or explicit references to the failed issue
2. Mark those as blocked; continue with all unblocked issues
3. Report blocked issues at each checkpoint

**Unrecoverable failures** (exit loop immediately):
- Three consecutive merge failures on the same PR
- Agent produced no PR (crash, timeout, no push)
- `git push` rejected on `$BASE` after fetch
- `$BASE` branch deleted or corrupted externally

---

## Constraints

- Never merge into `main` — all PRs target `$BASE`
- Never pause between loop cycles — proceed immediately after printing the checkpoint summary
- Never skip a failed issue's dependents — always analyze and block them
- Every agent must work in an isolated worktree
- Every PR must reference the issue it closes (`Closes #N`)
- Commit messages must follow `conventional-commit-message` sub-skill format
- Never mention Claude or add co-author lines in commit messages
- Agents spawn with `mode: "bypassPermissions"` so they can push and create PRs without prompting
- Never commit directly to develop or main — always work on the `worktree-agent-<issue>` branch
- **Never close issues** — issues are closed by the release process when staging merges to main
