---
name: roadmap
description: Survey the current work-in-flight (uncommitted state, branch role, open PRs, peer PRs, RCs, in-flight worktrees, existing tasks) and produce an approved task chain that takes the work all the way to "shipped". Read-only during planning. Presents the chain for approval and, on approval, optionally hands off to `/sessionkit:drive` for autonomous execution.
triggers:
  - "/roadmap"
  - "plan the rest"
  - "what's left to ship"
  - "map out the remaining steps"
  - "task out the path to done"
  - "wrap up current work"
allowed-tools: Bash, Read, Grep, Glob, TaskList, TaskGet, TaskCreate, TaskUpdate, AskUserQuestion, Skill
---

# Roadmap

Map the route from "where we are now" to "fully shipped" — or whatever the natural completion state is for the current work — and materialize it as an approved task chain. After approval, hand off to `/sessionkit:drive` for autonomous execution, or hand the chain back to the user to drive manually.

Companion to `/sessionkit:drive`:

- `/sessionkit:roadmap` (this skill) — surveys + plans + approves.
- `/sessionkit:drive` — executes an approved chain.

## Process

### 1. Survey current work-in-flight

Read-only. Run these in parallel:

```bash
# Uncommitted state
git status --porcelain

# Current branch
git branch --show-current

# Branch's relationship to remote
git log @{u}..HEAD --oneline 2>/dev/null   # local commits not pushed
git log HEAD..@{u} --oneline 2>/dev/null   # remote commits not pulled
git rev-parse --abbrev-ref @{u} 2>/dev/null # tracked upstream

# Base branch + epic mode
git config claude.flowkit.prBase           # epic base if set
git ls-remote --heads origin develop main  # which long-lived branches exist

# Open PRs targeting common bases
gh pr list --base develop --state open --json number,title,headRefName,reviewDecision,mergeStateStatus,isDraft 2>/dev/null
gh pr list --base main    --state open --json number,title,headRefName,reviewDecision,mergeStateStatus,isDraft 2>/dev/null
gh pr list --head "$(git branch --show-current)" --state open --json number,title,baseRefName,reviewDecision,mergeStateStatus 2>/dev/null

# Pipeline state (RC branches, latest tag)
git ls-remote --heads origin "rc/*" | awk '{print $2}' | sed 's|refs/heads/||'
git ls-remote --tags  origin "v[0-9]*" | awk '{print $2}' | sed 's|refs/tags/||' | sort -V | tail -1

# In-flight worktrees (isolated agents)
git worktree list

# Existing task list
```

Then call `TaskList` to see what's already tracked.

If `flowkit:pipeline-status` is available in this repo, prefer invoking it once via the `Skill` tool for the canonical pipeline view — it summarizes the data above into a single block.

### 2. Classify the state

Identify every state signal that applies (composable, not exclusive). Map each to the entry point of a sub-chain:

| Signal | Sub-chain entry |
|--------|-----------------|
| Uncommitted local changes (`git status` non-empty) | Commit → push → PR → review → merge → … |
| Local commits ahead of upstream | Push → PR → review → merge → … |
| Branch pushed, no PR open | Open PR → review → merge → … |
| Open PR for current branch | Self-review → merge → … |
| Peer PRs on same base (stack) | Merge-stack → … |
| Epic mode set (`claude.flowkit.prBase` non-empty) | Same as stack, then integration PR to base |
| `develop` ahead of `main` (release awaiting cut) | Bump versions → cut → release |
| RC branch exists on origin | Release (RC → main) |
| Latest release shipped, develop in sync | "Nothing to ship" — surface and offer alternatives |

### 3. Synthesize the linear/DAG plan

Compose the entry sub-chains into a single ordered chain. Standard step library — pick from these and stitch:

| Step | Skill / command |
|------|-----------------|
| Commit local changes | `/flowkit:commit` |
| Open PR for current branch | `/flowkit:open-pr` |
| Stage + commit + open PR in one shot | `/flowkit:pr` |
| Self-review the PR diff | `/review` (or manual read-through) |
| Merge a single PR | `/flowkit:merge-pr` |
| Merge a stacked PR set | `/swarmkit:merge-stack` |
| Verify the integrated state | manual: project's typecheck/test/lint on the feature branch |
| Promote epic → develop | `/flowkit:ship-epic` |
| Sync local develop with origin | `/flowkit:sync` |
| Bump per-plugin versions + tags | `/bump-versions` |
| Cut a release candidate | `/flowkit:cut` |
| Promote RC → main, tag, close issues | `/flowkit:release` |
| Cut + release in one shot (develop → main) | `/flowkit:ship` |
| Verify post-release pipeline state | `/flowkit:pipeline-status` |

**Canonical bubble-free release sequence.** When an epic is in flight (open `worktree-agent-*` PRs targeting a `feature/<slug>-<N>` branch), the standard chain is:

```
/swarmkit:merge-stack → verify (manual) → /flowkit:ship-epic → /flowkit:ship
```

`/flowkit:ship` aborts if open `worktree-agent-*` PRs still target the resolved base, so the verify step between `merge-stack` and `ship-epic` is a hard prerequisite — operators cannot collapse the chain into a single step. For releases with no epic in flight, `/flowkit:ship` alone (cut → release) is the entire chain.

For each step in the chain, write a task with:

- **subject** — imperative title (e.g. `Merge PR #777 to develop`).
- **description** — exact skill invocation (e.g. `Run /flowkit:merge-pr.`) or, for non-skill work, the concrete outcome (e.g. `Self-review the final diff. Confirm: bug fix is correct, no flowkit dependencies remain, PR body matches plugins/_shared/pr-body.md.`). Drive parses the description, so be unambiguous.
- **activeForm** — present-continuous form for the spinner.

Wire `blockedBy` so each step is unblocked only after its predecessor completes. Linear chains are the common case; only branch when the work genuinely forks.

### 4. Present the plan + ask approval

After all tasks are created, output a compact summary:

```
── Roadmap ────────────────────────────────────────
Goal: <one-sentence statement of what "done" means here>

Plan (<N> steps):
  1. <subject>            (skill: <skill or "manual">)
  2. <subject>            (...)
  ...

Estimated path: <ordered list of skill names that will run>
───────────────────────────────────────────────────
```

Then ask via `AskUserQuestion`:

- **question**: `Approve this roadmap?`
- **header**: `Roadmap`
- **options**:
  1. `Drive it for me` — invokes `/sessionkit:drive` immediately. Recommended.
  2. `I'll drive` — exits; user works the task list manually.
  3. `Modify` — user describes changes; regenerate the plan from step 3.
  4. `Cancel` — delete the created tasks and exit.

If only one step exists, fall back to plain text — the structured prompt is overkill for a single-action plan.

### 5. Act on the answer

- **Drive it for me** → invoke `Skill("sessionkit:drive")`. The drive skill picks up the just-created task list and executes it. Roadmap's job ends here.
- **I'll drive** → print the task IDs and a one-line reminder (`Run /sessionkit:drive when ready, or work the list manually.`) and exit.
- **Modify** → prompt the user for what to change. Update the task list (TaskUpdate to edit/delete, TaskCreate to add). Re-present from step 4.
- **Cancel** → for every task created in this invocation, `TaskUpdate` with `status: deleted`. Confirm and exit.

## Constraints

- **Read-only during steps 1–3.** Never mutate the repo, branches, tags, or PRs while planning. The plan is a proposal until the user approves.
- **Tasks created before approval are provisional.** If the user picks "Cancel", delete every task this invocation created.
- **Don't invent steps the project doesn't have.** Only reference skills and commands that exist in this repo / installed plugins. If the natural step is missing (no `/flowkit:cut` because flowkit isn't installed), surface that as a gap rather than silently stepping over it.
- **Never assume universal driving rules.** The driving contract lives in `/sessionkit:drive`'s SKILL.md and in this skill — do not assume the user has any global directive in `CLAUDE.md`. The skill must work for any installer.
- **One chain per invocation.** If the survey turns up two unrelated work threads (e.g. an in-flight PR *and* a separate untracked feature branch), ask which one to plan rather than producing a fork. The user can run roadmap again for the other thread.
- **Use named skills, not raw commands, where possible.** A task description that says "Run `/flowkit:cut`" is unambiguous to drive; a description that pastes the cut script is brittle.
