---
name: swarm-plus
description: Wrap /swarmkit:swarm with an automatic review/fix pass. After each swarm PR opens, dispatch a swarmkit-vendored reviewer; if the reviewer flags blockers or concerns, spawn a fresh worker to address them and update the PR. Single pass — stop after one reviewer + at-most-one fix round per PR.
triggers:
  - "swarm plus"
  - "swarm+"
  - "swarm with review"
  - "swarm and review"
  - "swarm review"
  - "swarm + review pass"
---

# Swarm Plus

Layer an automatic review/fix pass over `/swarmkit:swarm`. Same arg grammar; same isolation; same final state (open PRs awaiting human merge). The only addition: each PR gets one reviewer, and if the reviewer surfaces blockers or concerns, a fresh worker is spawned to push follow-up commits to the same branch.

### Runtime contract: builders always exit; fix-rounds always spawn a fresh worker

The harness terminates builder agents shortly after they emit their final task notification. Builder prompts still emit `STANDBY_READY` as a forward-compatibility hint in case the runtime ever supports persistent standby, but **the orchestrator MUST treat every builder as no-longer-addressable once the PR is reported**. SendMessage to a former builder consistently fails with "No agent named X is currently addressable."

**Canonical fix-round path: spawn-fresh-worker.** Whenever a reviewer's verdict is non-clean (blockers, concerns, or `[recommended]` coverage gaps), the orchestrator spawns a brand-new `general-purpose` agent in an isolated worktree, branches it from the existing PR head, and lets it apply the reviewer's findings. The original builder is never re-engaged.

**Why STANDBY_READY remains in builder prompts.** It is cheap, harmless under today's runtime (the builder emits the sentinel and is then terminated by the harness), and keeps the prompt forward-compatible if a future runtime version preserves agents past their last notification. The orchestrator should NOT attempt SendMessage on builders today — those calls will fail.

## Input

Identical to `/swarmkit:swarm`:

- No args → loop mode, all open issues → `main`
- Label text (e.g. `bug`, `priority:high`) → loop mode filtered by label → `main`
- Issue numbers (`12 15 18`, `#12 #15 #18`, range `12-18`) → one-shot mode → `main`
- `--model <tier>` (`sonnet`, `opus`) — model override for swarm agents (reviewer + worker have their own defaults; see below)
- `--base <branch>` — override default base branch
- `--review-only` — review only; never spawn a fix-round worker (useful for triage). The reviewer's findings stay inline in the final report.
- `--worker-model <tier>` — override model for the fix-round worker (default: `sonnet`). Every non-clean reviewer verdict spawns a fresh worker, so this knob applies to the canonical fix-round path.
- `--reviewer-model <tier>` — override reviewer model (default: `sonnet`)

## Process

### 0. Pre-flight: resolve verify command

> Resolved once at the start of the run, before any worker is dispatched.

Resolve the project's verify command once and reuse it for every worker prompt. This keeps swarm-plus useful in any repo, not just TS repos with `tsc`. Use this lookup chain (first hit wins):

1. **`.squadkit/config.json` `verifyCommand`** — repo-level explicit override. Read with `jq -r '.verifyCommand // empty' .squadkit/config.json` if the file exists.
2. **`package.json` `scripts.verify`** — common project-local convention. If present, the verify command is determined by the package manager: `yarn.lock` present → `yarn run verify`; `pnpm-lock.yaml` present → `pnpm run verify`; otherwise → `npm run verify`.
3. **Fallback** — `npx tsc -b --noEmit` for TS projects. "TS toolchain present" means `tsconfig.json` exists at the repo root. If neither of the above resolves AND `tsconfig.json` is absent, print a warning and instruct the worker to skip the verify step rather than running a command that will obviously fail. **Note:** projects that use `tsc` via a non-standard mechanism (e.g. a wrapper script, a monorepo tool, or a config file named differently) won't be detected by this check — those repos should set `verifyCommand` in `.squadkit/config.json` to opt in explicitly.

Record the resolved command as `<verify_command>` and interpolate it into the prompts in step 1 (builder prompt, forward-compat clause) and step 4 (fix-round worker prompt).

### 1. Run the swarm phase

**Builder prompt construction (swarm-plus constructs prompts directly).** swarm-plus does NOT invoke `/swarmkit:swarm` as a sub-skill. Instead, it follows the spawn pattern documented in `/swarmkit:swarm/SKILL.md` — reading its agent prompt structure, dependency graph logic, and verification steps — but constructs each builder Agent call itself with two minor modifications:

1. Each builder is spawned with a deterministic, addressable `name:` parameter: `swarm-builder-<issue>`. This is kept for forward compatibility with a future runtime that supports persistent standby; today it has no functional effect since the harness terminates the builder anyway.
2. A STANDBY clause is appended to every builder prompt (see below) for the same forward-compat reason.

This approach keeps `/swarmkit:swarm` completely unmodified while giving swarm-plus full control over name assignment and prompt injection.

Record `(issue, pr_number, head_branch, base_branch)` for each PR as it is produced.

**Standby instruction injection (forward-compat only).** swarm-plus appends the following STANDBY clause to the end of every builder prompt it constructs. **In today's runtime the harness terminates the builder shortly after it emits the final notification, so this clause is effectively a no-op** — but it is left in place so the prompt remains correct if a future runtime preserves agents past their last notification. Plain `/swarmkit:swarm` invocations continue to terminate at step 6 of the swarm prompt — this clause only appears in swarm-plus-constructed prompts.

> **STANDBY (swarm-plus only, forward-compat).** After reporting the PR URL, reply `STANDBY_READY` and then enter standby, awaiting an orchestrator SendMessage. If the harness terminates you instead of delivering a message, that is expected under the current runtime. If a message does arrive, it will be one of three:
>
> 1. `"Approved. Terminate."` — exit cleanly.
> 2. `"Review-only run. Terminate."` — exit cleanly without acting on anything.
> 3. A `REVIEWER FINDINGS` payload with explicit scope — apply the in-scope items (blockers, concerns, `[recommended]` coverage gaps), skip the out-of-scope items (nits, `[optional]`), run `<verify_command>` and the relevant test scope, commit (conventional-commit format, no Claude mentions, no co-author lines), `git push origin <head_branch>`, and optionally `gh pr comment <pr_number>` summarizing what was addressed and what was deferred. Then terminate.
>
> All swarm constraints still apply: never branch off `main` for the fix round (you are already on the PR's head branch in your worktree), never force-push, never close the issue manually.

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

**Verdict delivery contract.** Per the reviewer agent's contract (`plugins/swarmkit/agents/swarm-reviewer.md`), the reviewer `SendMessage`s its complete structured verdict to the parent (this orchestrator) before terminating. The idle notification alone does not carry the verdict text — wait for the `SendMessage` payload to parse the result and apply the skip-on-clean rule in step 3. If only an idle notification arrives with no accompanying `SendMessage` payload, treat the reviewer as having returned no output and note the missing review in the final summary.

Track each reviewer's agent ID against the PR it covers.

### 3. Decide whether to spawn a fix-round worker

When the reviewer's `SendMessage` payload arrives (delivered separately from the idle notification — see step 2's verdict delivery contract), parse its result and apply the **skip-on-clean** rule.

| Reviewer output | Action |
|-----------------|--------|
| Verdict `Approve` AND no blockers AND no concerns AND no `[recommended]` coverage gaps | No fix-round worker. PR stands as-is. Nits and `[optional]` coverage gaps are not actionable enough to warrant a fix round. |
| Any blockers | Spawn fix-round worker (see step 4). Blockers are mandatory. |
| Any concerns | Spawn fix-round worker. Concerns get addressed or explicitly deferred in a PR comment. |
| Coverage gaps flagged `[recommended]` | Spawn fix-round worker. Treat recommended coverage gaps as concerns. |
| `--review-only` flag set | Never spawn a fix-round worker, regardless of reviewer verdict. Reviewer output stays inline in the final report. |

Print one line announcing the decision per PR:

```
PR #1390: reviewer clean (no blockers/concerns) → no fix round
PR #1391: reviewer flagged 1 blocker, 2 concerns → spawning fresh worker
PR #1392: reviewer flagged 1 blocker → spawning fresh worker
```

### 4. Spawn the fix-round worker

For every PR whose reviewer verdict was non-clean (and `--review-only` is not set), spawn a fresh `general-purpose` agent with `isolation: worktree`, `mode: bypassPermissions`, `run_in_background: true`. Default model `sonnet`; override via `--worker-model`.

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
  3. Run `<verify_command>` (resolved in step 0) and the relevant test scope. Resolve any failures before proceeding — never push a red build.
  4. Commit with conventional-commit format (no Claude mentions, no co-author lines).
  5. Push to the same branch (`git push origin <head_branch>`) — auto-updates the PR.
  6. Optionally comment on the PR summarizing what was addressed and what was deferred:
     ```bash
     gh pr comment <pr_number> --body "Addressed reviewer feedback: <summary>. Deferred: <items with reasons>."
     ```
- Forbid: branching off `main`, force-pushing, rewriting prior commits, closing the issue manually.
- Termination: report the new commit SHAs and confirm `gh pr view <pr_number> --json commits` includes them.

### 5. Wait for all fix-round workers

Continue until every spawned fix-round worker reports completion. Verify the PR's HEAD has advanced:

```bash
gh pr view <pr_number> --json commits | jq '.commits[-1].oid'
```

For PRs with no fix round (clean reviewer verdict, or `--review-only`), no further action is needed.

### 6. Final report

```
── swarm-review complete ─────────────────────
PRs opened by swarm: #1390 #1391 #1392 #1393
  #1390: reviewed → clean → no fix round
  #1391: reviewed → 2 concerns → fresh worker pushed 2 commits
  #1392: reviewed → 1 blocker → fresh worker pushed 1 commit
  #1393: reviewed → 1 blocker → fresh worker pushed 1 commit
All PRs ready for human merge.
─────────────────────────────────────────────
```

Suggest next step: `/merge-pr` for one PR or `/merge-stack` for two or more.

## Failure modes

| Symptom | Handling |
|---------|----------|
| Swarm agent fails to produce a PR | Skip review/fix round for that issue; report in final summary |
| Reviewer crashes or returns no output | Note the missing review in the final summary; leave PR open without a fix pass |
| Fix-round worker push rejected (branch advanced underneath) | Worker re-fetches and rebases (`git fetch origin <head>; git rebase origin/<head>`); if conflicts arise, abort and report to user |
| Fix-round worker introduces new test failures | Worker MUST resolve before push — never push a red build |
