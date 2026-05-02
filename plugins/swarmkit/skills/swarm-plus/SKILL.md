---
name: swarm-plus
description: Wrap /swarmkit:swarm with an automatic review/fix pass. After each swarm PR opens, dispatch a swarmkit-vendored reviewer; if the reviewer flags blockers or concerns, re-engage the original builder via SendMessage to address them and update the PR. Single pass — stop after one reviewer + at-most-one fix round per PR.
triggers:
  - "swarm plus"
  - "swarm+"
  - "swarm with review"
  - "swarm and review"
  - "swarm review"
  - "swarm + review pass"
---

# Swarm Plus

Layer an automatic review/fix pass over `/swarmkit:swarm`. Same arg grammar; same isolation; same final state (open PRs awaiting human merge). The only addition: each PR gets one reviewer, and if the reviewer surfaces blockers or concerns, the original builder is re-engaged via SendMessage to push follow-up commits to the same branch.

### Keep-alive architecture

Builders do not terminate after reporting their PR URL — they enter standby awaiting an orchestrator message. The orchestrator routes the reviewer's verdict back to the original builder via SendMessage:

- **Reviewer clean** → `"Approved. Terminate."` — builder exits cleanly.
- **Reviewer flagged blockers / concerns / `[recommended]` coverage gaps** → reviewer findings forwarded verbatim with explicit scope. Builder applies, pushes, comments on the PR, terminates.
- **`--review-only` set** → `"Review-only run. Terminate."` — builder exits without acting on findings.

**Why keep-alive**: the builder already has every relevant file loaded, the design rationale in working memory, and the issue acceptance criteria internalized. Re-engaging it via SendMessage saves an entire spawn-and-orient cycle per PR with non-clean review.

**Cost tradeoff**: peak agent concurrency roughly doubles during the review window — on a 5-PR run, up to 10 alive concurrently (5 builders in standby + 5 reviewers) instead of 5+5 sequential. Acceptable for the latency win.

**Fallback to spawn-fresh-worker**: if the original builder is no longer alive (crashed at PR creation, or `verify_agent.sh` recovered the PR after the builder failed to push), the orchestrator falls back to the legacy spawn-fresh-worker path. `--worker-model` continues to apply on this fallback path only.

## Input

Identical to `/swarmkit:swarm`:

- No args → loop mode, all open issues → `develop`
- Label text (e.g. `bug`, `priority:high`) → loop mode filtered by label → `develop`
- Issue numbers (`12 15 18`, `#12 #15 #18`, range `12-18`) → one-shot mode → `develop`
- `--model <tier>` (`sonnet`, `opus`) — model override for swarm agents (reviewer + worker have their own defaults; see below)
- `--base <branch>` — override default base branch
- `--review-only` — review only; never act on findings (useful for triage). Each builder still receives a `"Review-only run. Terminate."` SendMessage so it exits cleanly from standby.
- `--worker-model <tier>` — override model **for the fallback spawn-fresh-worker path only** (default: `sonnet`). On the default keep-alive path the builder is re-engaged with whatever model `--model` selected; this knob has no effect there. Kept as a knob for the fallback case.
- `--reviewer-model <tier>` — override reviewer model (default: `sonnet`)

## Process

### 0. Pre-flight: resolve verify command

> Resolved once at the start of the run, before any worker is dispatched.

Resolve the project's verify command once and reuse it for every worker prompt. This keeps swarm-plus useful in any repo, not just TS repos with `tsc`. Use this lookup chain (first hit wins):

1. **`.squadkit/config.json` `verifyCommand`** — repo-level explicit override. Read with `jq -r '.verifyCommand // empty' .squadkit/config.json` if the file exists.
2. **`package.json` `scripts.verify`** — common project-local convention. If present, the verify command is determined by the package manager: `yarn.lock` present → `yarn run verify`; `pnpm-lock.yaml` present → `pnpm run verify`; otherwise → `npm run verify`.
3. **Fallback** — `npx tsc -b --noEmit` for TS projects. "TS toolchain present" means `tsconfig.json` exists at the repo root. If neither of the above resolves AND `tsconfig.json` is absent, print a warning and instruct the worker to skip the verify step rather than running a command that will obviously fail. **Note:** projects that use `tsc` via a non-standard mechanism (e.g. a wrapper script, a monorepo tool, or a config file named differently) won't be detected by this check — those repos should set `verifyCommand` in `.squadkit/config.json` to opt in explicitly.

Record the resolved command as `<verify_command>` and interpolate it into the prompts in step 1 (builder standby instruction) and step 4 (fallback worker prompt).

### 1. Run the swarm phase

Invoke `/swarmkit:swarm` with the same args (excluding `--review-only`, `--worker-model`, and `--reviewer-model` — those are swarm-plus-only flags). Track the agent IDs and the issues each agent owns. Record `(issue, pr_number, head_branch, base_branch, builder_agent_name)` for each PR as it is produced.

**Builder naming (required for SendMessage re-engagement).** Each builder must be spawned with an addressable `name:` parameter so the orchestrator can route reviewer findings back to it via SendMessage. Use a deterministic naming scheme tied to the issue number, e.g. `swarm-builder-<issue>`. Record the name alongside the PR record.

**Standby instruction injection (do NOT change `/swarmkit:swarm` itself).** swarm-plus injects an additional sentence at the end of every builder prompt it constructs, telling the builder to NOT terminate after reporting the PR URL. The default `/swarmkit:swarm` workflow stops at "Report the PR URL" — swarm-plus extends this with a standby clause:

> **STANDBY (swarm-plus only).** After reporting the PR URL, do NOT terminate. Enter standby and await an orchestrator SendMessage. You will receive one of three messages:
>
> 1. `"Approved. Terminate."` — exit cleanly.
> 2. `"Review-only run. Terminate."` — exit cleanly without acting on anything.
> 3. A `REVIEWER FINDINGS` payload with explicit scope — apply the in-scope items (blockers, concerns, `[recommended]` coverage gaps), skip the out-of-scope items (nits, `[optional]`), run `<verify_command>` and the relevant test scope, commit (conventional-commit format, no Claude mentions, no co-author lines), `git push origin <head_branch>`, and optionally `gh pr comment <pr_number>` summarizing what was addressed and what was deferred. Then terminate.
>
> All swarm constraints still apply: never branch off `develop` for the fix round (you are already on the PR's head branch in your worktree), never force-push, never close the issue manually.

This injection lives in swarm-plus's prompt construction only — it does **not** modify `/swarmkit:swarm`'s default behavior. Plain `/swarmkit:swarm` invocations continue to terminate at step 6 of the swarm prompt.

Do NOT block on every swarm agent before spawning reviewers. As each swarm agent's task notification arrives:

1. Verify the PR exists: `gh pr view <pr_number> --json url,headRefName,baseRefName,state`
2. Fetch the original issue body: `gh issue view <issue> --json body --jq '.body'`
3. Determine builder liveness — if the agent's notification was a *final completion* (the builder did not enter standby; e.g. the swarm-plus standby injection was overridden, or `verify_agent.sh` recovered the PR because the builder crashed at PR creation), mark `builder_alive: false` for this PR. Otherwise the builder is in standby and `builder_alive: true`.
4. Spawn a reviewer for that PR (see step 2). Continue handling other notifications in parallel.

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

### 3. Decide what to send the builder

When a reviewer's task notification arrives, parse its result. Apply the **skip-on-clean** rule. Note: the builder is in standby in every case below (unless `builder_alive: false` — see fallback in step 4) and must always receive a SendMessage so it can exit cleanly. Never abandon a standby builder.

| Reviewer output | Builder message |
|-----------------|-----------------|
| Verdict `Approve` AND no blockers AND no concerns AND no `[recommended]` coverage gaps | SendMessage `"Approved. Terminate."` — builder exits. Nits and `[optional]` coverage gaps are not actionable enough to warrant a fix round. |
| Any blockers | SendMessage with reviewer findings + scope. Blockers are mandatory. |
| Any concerns | SendMessage with reviewer findings + scope. Concerns get addressed or explicitly deferred. |
| Coverage gaps flagged `[recommended]` | SendMessage with reviewer findings + scope. Treat recommended coverage gaps as concerns. |
| `--review-only` flag set | SendMessage `"Review-only run. Terminate."` regardless of reviewer verdict — builder exits without acting on findings. |

Print one line announcing the decision per PR:

```
PR #1390: reviewer clean (no blockers/concerns) → SendMessage "Approved. Terminate."
PR #1391: reviewer flagged 1 blocker, 2 concerns → SendMessage findings to swarm-builder-<issue>
PR #1392: builder no longer alive → falling back to spawn-fresh-worker
```

### 4. Re-engage builder (or fallback to spawn worker)

**Default path: SendMessage to the standby builder.** When `builder_alive: true` for the PR, route the message determined in step 3 directly to the builder by name. The builder's standby instructions (injected in step 1) tell it how to interpret each message.

For the findings-payload case, the SendMessage body MUST include:

- The **PR number** and **head branch** (e.g. `worktree-agent-42`) — the builder is already on this branch in its worktree, but include explicitly so the message is self-contained.
- The **full reviewer output** verbatim under a `REVIEWER FINDINGS` section.
- Explicit scope:
  - **In scope**: blockers (mandatory), concerns (address or explicitly defer with stated reason in a PR comment), reviewer-recommended coverage gaps.
  - **Out of scope**: nits (skip unless trivially co-located with a fix), `[optional]` coverage gaps, unrelated cleanups, scope creep.

The builder's standby instructions already cover the action steps (verify, commit, push, optional PR comment, terminate) — no need to re-state them in the SendMessage.

**Fallback path: spawn a fresh worker.** Trigger the legacy spawn-fresh-worker path **only** when:

- `builder_alive: false` for this PR (builder crashed at PR creation, or `verify_agent.sh` recovered the PR after the builder failed to push, or the builder somehow exited without entering standby).
- AND `--review-only` is **not** set (review-only never spawns workers, regardless of liveness).

If `--review-only` is set and `builder_alive: false`, do nothing — the reviewer output stays inline in the final report and no fix round happens.

For the fallback, spawn a `general-purpose` agent with `isolation: worktree`, `mode: bypassPermissions`, `run_in_background: true`. Default model `sonnet`; override via `--worker-model` (this is the only path where `--worker-model` takes effect).

The fallback worker prompt MUST:

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
  3. Run `<verify_command>` (resolved in step 1a) and the relevant test scope. Resolve any failures before proceeding — never push a red build.
  4. Commit with conventional-commit format (no Claude mentions, no co-author lines).
  5. Push to the same branch (`git push origin <head_branch>`) — auto-updates the PR.
  6. Optionally comment on the PR summarizing what was addressed and what was deferred:
     ```bash
     gh pr comment <pr_number> --body "Addressed reviewer feedback: <summary>. Deferred: <items with reasons>."
     ```
- Forbid: branching off `develop`, force-pushing, rewriting prior commits, closing the issue manually.
- Termination: report the new commit SHAs and confirm `gh pr view <pr_number> --json commits` includes them.

### 5. Wait for all builders / fallback workers

Continue until every re-engaged builder and every fallback worker reports completion. For PRs whose builder received `"Approved. Terminate."` or `"Review-only run. Terminate."`, simply confirm the builder's task notification arrived. For PRs that received a findings payload (or that fell back to a fresh worker), verify the PR's HEAD has advanced:

```bash
gh pr view <pr_number> --json commits | jq '.commits[-1].oid'
```

### 6. Final report

```
── swarm-review complete ─────────────────────
PRs opened by swarm: #1390 #1391 #1392 #1393
  #1390: reviewed → clean → builder terminated cleanly
  #1391: reviewed → 2 concerns → builder pushed 2 commits (re-engaged)
  #1392: reviewed → 1 blocker → builder pushed 1 commit (re-engaged)
  #1393: reviewed → 1 blocker → fallback worker pushed 1 commit (builder was no longer alive)
All PRs ready for human merge.
─────────────────────────────────────────────
```

Suggest next step: `/merge-pr` for one PR or `/merge-stack` for two or more.

## Constraints

- **Single pass** — no reviewer-after-fix re-review. The user can manually trigger another review with `/review <pr>` if desired.
- **Skip-on-clean preserves SendMessage** — even on a clean approval, the orchestrator must SendMessage `"Approved. Terminate."` to the standby builder. Never abandon a builder in standby.
- **Builder never re-branches** — the re-engaged builder is already on the PR's head branch in its worktree; it must not branch off `develop` or anything else for the fix round. The fallback worker (if triggered) branches off the existing PR head, not `develop`.
- **`/swarmkit:swarm` default behavior is untouched** — swarm-plus injects its standby clause into the builder prompts it constructs. Plain `/swarmkit:swarm` invocations still terminate at step 6 of the swarm prompt.
- **`--worker-model` only applies on the fallback path** — on the default keep-alive path the builder runs under whatever `--model` selected. The flag is kept for the fallback case; do not assume it influences re-engaged builders.
- **Reviewer output stays inline, never posted as a PR comment** by the reviewer itself. The builder (or fallback worker) is the only sub-agent that may comment on the PR (and only with a brief "addressed feedback" summary).
- **Never merge** any PR — final state is open PRs awaiting human merge.
- **Never close issues** — `Closes #N` in PR bodies handles it on merge.
- **Defer rather than guess** — if the reviewer's findings are ambiguous (e.g. "consider X"), the builder should explicitly defer in a PR comment rather than implement guesses.
- All swarm constraints from `/swarmkit:swarm` apply transitively: worktree isolation, conventional commits, no Claude/co-author mentions, no absolute repo paths in agent prompts, never commit directly to develop or main.

## Failure modes

| Symptom | Handling |
|---------|----------|
| Swarm agent fails to produce a PR | Skip review/fix round for that issue; report in final summary |
| Reviewer crashes or returns no output | SendMessage `"Approved. Terminate."` to the standby builder so it exits cleanly; note the missing review in the final summary; leave PR open without a fix pass |
| Builder unresponsive in standby (SendMessage delivered but no notification within reasonable window) | Treat as `builder_alive: false` and trigger the fallback spawn-fresh-worker path. Surface a warning in the final summary so the user knows the standby builder may still be holding resources |
| SendMessage call fails (builder agent ID no longer addressable) | Treat as `builder_alive: false` and trigger the fallback spawn-fresh-worker path |
| Builder crashed before entering standby (no PR pushed; recovered by `verify_agent.sh`) | `builder_alive: false` from the start; if reviewer flags issues, fallback worker handles the fix round |
| Builder pushed PR but exited before standby (standby clause was missed/ignored) | `builder_alive: false`; fallback worker handles any fix round |
| Re-engaged builder push rejected (branch advanced underneath) | Builder re-fetches and rebases (`git fetch origin <head>; git rebase origin/<head>`); if conflicts arise, abort and report to user |
| Re-engaged builder (or fallback worker) introduces new test failures | Sub-agent MUST resolve before push — never push a red build |
