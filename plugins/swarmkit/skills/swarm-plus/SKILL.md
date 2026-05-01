---
name: swarm-plus
description: Wrap /swarmkit:swarm with an automatic review/fix pass. After each swarm PR opens, dispatch a swarmkit-vendored reviewer; if the reviewer flags blockers or concerns, dispatch a worker to address them and update the PR. Single pass — stop after one reviewer + at-most-one worker per PR.
triggers:
  - "swarm plus"
  - "swarm+"
  - "swarm with review"
  - "swarm and review"
  - "swarm review"
---

# Swarm Plus

Layer an automatic review/fix pass over `/swarmkit:swarm`. Same arg grammar; same isolation; same final state (open PRs awaiting human merge). The only addition: each PR gets one reviewer, and if the reviewer surfaces blockers or concerns, one worker pushes follow-up commits to the same branch.

## Input

Identical to `/swarmkit:swarm`:

- No args → loop mode, all open issues → `develop`
- Label text (e.g. `bug`, `priority:high`) → loop mode filtered by label → `develop`
- Issue numbers (`12 15 18`, `#12 #15 #18`, range `12-18`) → one-shot mode → `develop`
- `--model <tier>` (`sonnet`, `opus`) — model override for swarm agents (reviewer + worker have their own defaults; see below)
- `--base <branch>` — override default base branch
- `--review-only` — review only; never dispatch worker (useful for triage)
- `--worker-model <tier>` — override worker model (default: `sonnet`)
- `--reviewer-model <tier>` — override reviewer model (default: `sonnet`)

## Process

### 1. Run the swarm phase

Invoke `/swarmkit:swarm` with the same args (excluding `--review-only`, `--worker-model`, and `--reviewer-model` — those are swarm-plus-only flags). Track the agent IDs and the issues each agent owns. Record `(issue, pr_number, head_branch, base_branch)` for each PR as it is produced.

Do NOT block on every swarm agent before spawning reviewers. As each swarm agent's task notification arrives:

1. Verify the PR exists: `gh pr view <pr_number> --json url,headRefName,baseRefName,state`
2. Fetch the original issue body: `gh issue view <issue> --json body --jq '.body'`
3. Spawn a reviewer for that PR (see step 2). Continue handling other notifications in parallel.

### 2. Spawn reviewer per PR

Spawn the **`swarmkit:swarm-reviewer`** agent with `run_in_background: true`. Default model `sonnet`; override via `--reviewer-model`.

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

Track each reviewer's agent ID against the PR it covers.

### 3. Decide whether to spawn a worker

When a reviewer's task notification arrives, parse its result. Apply the **skip-on-clean** rule:

| Reviewer output | Worker action |
|-----------------|---------------|
| Verdict `Approve` AND no blockers AND no concerns AND no `[recommended]` coverage gaps | **Skip worker.** Nits and `[optional]` coverage gaps are not actionable enough to warrant a worker round. |
| Any blockers | **Spawn worker.** Blockers are mandatory. |
| Any concerns | **Spawn worker.** Concerns get addressed or explicitly deferred. |
| Coverage gaps flagged `[recommended]` | **Spawn worker.** Treat recommended coverage gaps as concerns. |
| `--review-only` flag set | Skip regardless. |

Print one line announcing the decision per PR:

```
PR #1390: reviewer clean (no blockers/concerns) → skipping worker
PR #1391: reviewer flagged 1 blocker, 2 concerns → dispatching worker
```

### 4. Spawn worker

For each PR that needs follow-up work, spawn a `general-purpose` agent with `isolation: worktree`, `mode: bypassPermissions`, `run_in_background: true`. Default model `sonnet`; override via `--worker-model`.

The worker prompt MUST:

- Include the **PR number** and **head branch** (e.g. `worktree-agent-42`).
- Include the **full reviewer output** verbatim under a `REVIEWER FINDINGS` section.
- State explicit scope:
  - **In scope**: blockers (mandatory), concerns (address or explicitly defer with stated reason in a PR comment), reviewer-recommended coverage gaps.
  - **Out of scope**: nits (skip unless trivially co-located with a fix), `[optional]` coverage gaps, unrelated cleanups, scope creep.
- Instruct the worker to:
  1. Branch from the **existing PR branch**, NOT from `develop`:
     ```bash
     git fetch origin <head_branch>
     git checkout -B <head_branch> origin/<head_branch>
     ```
  2. Apply the changes.
  3. Run `npx tsc -b --noEmit` and the relevant test scope. Resolve any failures before proceeding — never push a red build.
  4. Commit with conventional-commit format (no Claude mentions, no co-author lines).
  5. Push to the same branch (`git push origin <head_branch>`) — auto-updates the PR.
  6. Optionally comment on the PR summarizing what was addressed and what was deferred:
     ```bash
     gh pr comment <pr_number> --body "Addressed reviewer feedback: <summary>. Deferred: <items with reasons>."
     ```
- Forbid: branching off `develop`, force-pushing, rewriting prior commits, closing the issue manually.
- Termination: report the new commit SHAs and confirm `gh pr view <pr_number> --json commits` includes them.

### 5. Wait for all workers

Continue until every dispatched worker reports completion. Verify each PR's HEAD has advanced:

```bash
gh pr view <pr_number> --json commits | jq '.commits[-1].oid'
```

### 6. Final report

```
── swarm-review complete ─────────────────────
PRs opened by swarm: #1390 #1391 #1392
  #1390: reviewed → clean → no worker
  #1391: reviewed → 2 concerns → worker pushed 2 commits
  #1392: reviewed → 1 blocker → worker pushed 1 commit
All PRs ready for human merge.
─────────────────────────────────────────────
```

Suggest next step: `/merge-pr` for one PR or `/merge-stack` for two or more.

## Constraints

- **Single pass** — no reviewer-after-worker re-review. The user can manually trigger another review with `/review <pr>` if desired.
- **Skip-on-clean** — never dispatch a worker against a clean approval. Manufactured churn is worse than a no-op.
- **Worker branches off PR head, never off `develop`** — commits must stack on the existing PR.
- **Reviewer output stays inline, never posted as a PR comment** by the reviewer itself. The worker is the only sub-agent that may comment on the PR (and only with a brief "addressed feedback" summary).
- **Never merge** any PR — final state is open PRs awaiting human merge.
- **Never close issues** — `Closes #N` in PR bodies handles it on merge.
- **Defer rather than guess** — if the reviewer's findings are ambiguous (e.g. "consider X"), the worker should explicitly defer in a PR comment rather than implement guesses.
- All swarm constraints from `/swarmkit:swarm` apply transitively: worktree isolation, conventional commits, no Claude/co-author mentions, no absolute repo paths in agent prompts, never commit directly to develop or main.

## Failure modes

| Symptom | Handling |
|---------|----------|
| Swarm agent fails to produce a PR | Skip review/worker for that issue; report in final summary |
| Reviewer crashes or returns no output | Note in final summary; leave PR open without worker pass |
| Worker push rejected (branch advanced underneath) | Worker re-fetches and rebases (`git fetch origin <head>; git rebase origin/<head>`); if conflicts arise, abort and report to user |
| Worker introduces new test failures | Worker MUST resolve before push — never push a red build |
