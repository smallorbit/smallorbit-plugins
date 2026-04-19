---
name: squad
description: "EXPERIMENTAL — requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1. Spawn parallel agents for GitHub issues using the Agent Teams API instead of isolated worktrees. Same arg grammar as swarmkit:swarm. See epic #285 and https://code.claude.com/docs/en/agent-teams."
---

# squad Skill (Experimental)

> **Experimental**: This skill uses the Claude Code Agent Teams API, which must be explicitly enabled.
> Reference: [Agent Teams docs](https://code.claude.com/docs/en/agent-teams) | Epic: #285

Spawn parallel team agents for GitHub issues: $ARGUMENTS

## Preflight

Before doing anything else, check that the required environment variable is set:

```bash
if [[ -z "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" ]]; then
  echo "Agent Teams API is not enabled."
  echo ""
  echo "Run: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  echo ""
  echo "Then re-run this skill."
  exit 1
fi
```

If the variable is unset or empty, abort immediately with the message above. Do NOT fall through to `swarmkit:swarm` or any other skill.

---

## Arguments

Parse `$ARGUMENTS` to determine the mode. The grammar is identical to `swarmkit:swarm`:

- **No arguments** → **loop mode**, all open issues → `develop`
- **Label text** (non-numeric, e.g. `bug`, `priority:high`) → **loop mode**, filtered by label → `develop`
- **Issue numbers** (`12 15 18`, `#12 #15 #18`, range `12-18`) → **one-shot mode**, specific issues → `develop`
- `--model <tier>` (`sonnet`, `opus`) → model override for all agents
- `--base <branch>` → override default base branch

---

## Setup

_Stub — to be filled in by a downstream task (epic #285)._

Ensure the base branch exists and is up to date. At minimum:

```bash
git fetch origin
```

Verify `develop` exists on the remote:

```bash
git ls-remote --exit-code origin develop
```

Any additional Agent Teams-specific setup (e.g., team registration, capability declarations) will be specified in a subsequent task.

---

## One-Shot Mode

_Stub — to be filled in by a downstream task (epic #285)._

Used when explicit issue numbers are provided. The intent is to dispatch Agent Teams instances for the given set of issues, open PRs, and report results.

Key differences from `swarmkit:swarm` that will be specified downstream:
- Team member prompts (orchestrator + implementer roles)
- Agent Teams API invocation instead of worktree spawn
- Halt and cleanup behavior specific to the teams API

Until fully implemented, this section serves as a placeholder. Do not attempt to execute this mode — refer the user to `swarmkit:swarm` for production use.

---

## Loop Mode

_Stub — to be filled in by a downstream task (epic #285)._

Used when no issue numbers are given (no args or label filter). The intent is to continuously clear the board using Agent Teams instead of isolated-worktree agents.

Key differences from `swarmkit:swarm` that will be specified downstream:
- Continuous loop orchestration via the teams API
- Team-aware checkpoint reporting
- Halt and cleanup when the board is clear or an unrecoverable failure occurs

Until fully implemented, this section serves as a placeholder. Do not attempt to execute this mode — refer the user to `swarmkit:swarm` for production use.

---

## Dispatch Loop

The lead agent orchestrates the team for the entire run. It does not fire-and-forget — it stays active from initial fetch through teardown, reading teammate status via the Agent Teams mailbox and spawning/retiring teammates in response to completion messages.

### 1. Initial fetch

Before spawning anyone, the lead builds a starting batch of issues using swarmkit sub-skills:

- `swarmkit:gh-fetch-issues` — pull the open issue list, honoring label filters and the on-hold exclusion
- `swarmkit:issue-rank` — order the list by priority, specificity, architectural impact, and testability

The ranked list becomes the **target set**. Dependency edges between issues (e.g. stacked downstream work) are preserved so the lead can tell which issues are currently unblocked.

### 2. Spawn phase

Once the target set is known:

1. Spawn the reviewer **once** at the start of the run. Only one reviewer exists for the lifetime of the team:

   ```
   SpawnTeammate({name: "reviewer", role: "reviewer"})
   ```

2. For each currently unblocked issue in the target set, spawn a builder named `builder-<issue>`:

   ```
   SpawnTeammate({name: "builder-<issue>", role: "builder", issue: "<issue>"})
   ```

Concurrency is capped by the number of simultaneously unblocked issues. The lead does not spawn a builder whose upstream issue is still in-flight — it waits for the `pushed` signal (see Builder Teammate Contract) before releasing the downstream builder.

### 3. Watch phase

The lead blocks on its mailbox and reacts to completion messages from builders. When a builder reports `<issue> completed, PR: <url>`:

1. Re-evaluate the target set:
   - Remove the completed issue
   - Identify any issues that were blocked on it and are now unblocked
2. For each newly unblocked issue, spawn a new `builder-<issue>` teammate (step 2)
3. If the target set is empty, proceed to teardown

The lead reads teammate status by consuming messages on its mailbox (the Agent Teams `ReceiveMessage` primitive). It does **not** poll teammates directly — all coordination flows through messages.

### 4. Mode-specific termination

- **One-shot mode** — exits as soon as every issue in the initial target set has a PR. No re-fetching.
- **Loop mode** — after the current target set drains, the lead re-runs `swarmkit:gh-fetch-issues` + `swarmkit:issue-rank` and repeats the dispatch cycle. It exits only when the board is clear (no open, non-on-hold issues match the filter).

### 5. Lead stays active

The lead never backgrounds itself. It remains the single coordinator for the entire run — spawning teammates, watching the mailbox, and making dispatch decisions — until teardown (issues #277, #278).

---

## Builder Teammate Contract

A builder is a short-lived teammate responsible for shipping exactly one issue. It is spawned by the lead as `builder-<issue>` and exits once its PR is up and it has notified any downstream teammate.

### Workflow

1. **Claim the assigned issue** on the Agent Teams shared task list. The claim is atomic — if another teammate has already claimed this issue, abort.

2. **Worktree setup** — identical to `swarmkit:swarm`:
   - Independent issues branch from `develop`:
     ```bash
     git checkout -b worktree-agent-<issue> origin/develop
     ```
   - Downstream issues branch from their upstream's agent branch:
     ```bash
     git checkout -b worktree-agent-<issue> origin/worktree-agent-<upstream-issue>
     ```
   - Safety check — abort if not running inside an isolated worktree:
     ```bash
     [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: Not in isolated worktree. Aborting." && exit 1
     ```

3. **Implement the issue changes.** Use relative paths only from CWD. Stay scoped to the issue's acceptance criteria.

4. **Request review** by sending the reviewer the issue number and the diff path, then wait for a response:

   ```
   SendMessage({to: "reviewer", message: "<issue>#<diff-path>"})
   ```

   Block on the mailbox until the reviewer replies with `approve` or `revise: <reasons>`.

5. **On `approve`**:
   - Commit using `swarmkit:conventional-commit-message` format. No Claude mentions, no co-author lines.
   - Push the branch
   - Create the PR targeting the correct base (`develop` for independent issues, `worktree-agent-<upstream>` for stacked)

6. **On `revise: <reasons>`**:
   - Address the feedback
   - Re-request review (repeat step 4)
   - Repeat until the reviewer responds `approve`

7. **Notify**:
   - After a successful push, notify any downstream builder so they can rebase onto the updated upstream:
     ```
     SendMessage({to: "builder-<downstream>", message: "pushed"})
     ```
   - Report completion to the lead:
     ```
     SendMessage({to: "lead", message: "<issue> completed, PR: <url>"})
     ```

### Upstream → downstream notify protocol

This protocol **supplements** the stacked-branching model from `swarmkit:swarm`; it does **not** replace it.

- The downstream builder still branches from `worktree-agent-<upstream-issue>` at start, just as in the non-teams swarm.
- When the downstream receives `pushed` from its upstream, it rebases onto the latest upstream tip:
  ```bash
  git fetch origin worktree-agent-<upstream>
  git rebase origin/worktree-agent-<upstream>
  ```
- If the `pushed` message never arrives (upstream delayed, crashed, or finishes late), the downstream does **not stall**. It continues on its initial (stale) upstream snapshot. Stacking is a best-effort optimization, not a gating dependency.

---

## Reviewer Teammate Contract

The reviewer is the single long-running auditor for the team. It never writes to the filesystem, never creates PRs, and never reads GitHub state.

### Lifecycle

- **Spawned once** by the lead at the start of the run, with name `reviewer`
- **Long-running** — persists for the entire team run, serving audit requests from every builder that comes and goes
- **Shut down** during teardown (issues #277, #278)

### Workflow

1. **Wait for an audit request.** Block on the mailbox (`ReceiveMessage`).

2. **Parse the request.** Builders send structured payloads of the form:

   ```
   {from: "builder-N", issue: "N", branch: "worktree-agent-N", diff-path: "<worktree path>"}
   ```

3. **Read the diff** directly from the builder's worktree — no filesystem writes, no `git checkout`:

   ```bash
   git -C <diff-path> diff develop...HEAD
   ```

4. **Audit against the issue spec.** Check the diff against the acceptance criteria on the referenced issue:
   - Is the scope correct? (no extra files, no unrelated refactors)
   - Any obvious bugs?
   - Are tests present where the spec calls for them?

5. **Respond** to the requesting builder:
   - Approve:
     ```
     SendMessage({to: "builder-N", message: "approve"})
     ```
   - Request revisions with concise, actionable reasons:
     ```
     SendMessage({to: "builder-N", message: "revise: <concise actionable reasons>"})
     ```

6. **Return to step 1** and serve the next audit request.

### Hard constraints

- **Never creates PRs.** Review happens before push — the builder owns the PR.
- **Never reads GitHub state.** No `gh pr view`, no fetching PR comments, no interaction with github.com.
- **Read-only on the filesystem.** The reviewer may `git diff` and `git log` inside builder worktrees, but must not write, stage, commit, or check out.
- **Does not use the shared repo worktree.** The reviewer audits from builder worktree paths it receives in audit requests.

### Out of scope for v1

- Post-PR GitHub review (leave review comments on the PR itself)
- Reviewer writing fixes on behalf of the builder
- Reviewer coordinating across multiple in-flight builders (it serves requests one at a time, in mailbox order)

---

## Halt and Report

### Crash detection

The lead polls teammate health via the Agent Teams API (mailbox responsiveness or an explicit probe). On detection of any of the following, the lead halts immediately:

- Any builder teammate crash
- Reviewer teammate crash
- Mailbox delivery failure (send returns error after N retries)
- Teammate unresponsive beyond configurable timeout

**No auto-respawn, no retry, no continuing with surviving teammates.**

### State report

On halt, the lead prints:

```
── squad halted ──────────────────────────────
Cause: <what crashed and how>
PRs opened this run: <list with URLs>
In-flight builders: <list with issue numbers and worktree paths>
Surviving teammates: <names>

Recovery:
  1. Review opened PRs — they are safe to merge
  2. Inspect in-flight worktrees under .claude/worktrees/ for partial work
  3. Run: /clean-worktrees to discard partial state
  4. Re-run: /squad <args> to resume
──────────────────────────────────────────────
```

After printing the state report, the lead proceeds to teardown.

### Explicit non-goals for v1

- No auto-respawn of crashed teammates (deferred to v2)
- No partial-success continuation — one crash halts entire run
- No automatic cleanup on halt — teardown runs but in-flight worktrees may contain uncommitted work the user should inspect first

---

## Teardown

Runs **regardless of success or halt**. Every step must be idempotent — running teardown twice must not error or leave the repo in a worse state.

### Steps (in order)

1. **Shut down teammates cleanly** — iterate the team roster, invoke the Agent Teams shutdown API for each teammate (builders first, then reviewer):

   ```
   ShutdownTeammate({name: "builder-<issue>"})   // repeat for each builder
   ShutdownTeammate({name: "reviewer"})
   ```

   If a teammate is already gone (crashed or already exited), the call is a no-op.

2. **Invoke `clean-worktrees` sub-skill** — reuses existing logic to remove all `worktree-agent-*` worktrees, delete orphan local branches, and restore the caller's branch:

   ```
   swarmkit:clean-worktrees
   ```

3. **Unset scoped git config** — unset `claude.prBase` if it was set for this operation (mirrors `swarmkit:swarm` loop-mode teardown):

   ```bash
   git config --unset claude.prBase 2>/dev/null || true
   ```

4. **Final summary** — print what ran, which PRs are open for review, and any in-flight work needing manual inspection (in halt case):

   ```
   ── squad complete ────────────────────────────
   Issues resolved: <count>
   PRs open for review: <list with URLs>
   In-flight worktrees requiring inspection: <list or "none">
   ──────────────────────────────────────────────
   ```

### Out of scope

- Closing or merging PRs — left open for human review
- Deleting remote branches — only local worktrees and local branches are cleaned

---

## Constraints

- This skill is experimental and subject to breaking changes as the Agent Teams API evolves
- Never fall through to `swarmkit:swarm` — if the preflight fails, abort
- Never merge into `main` directly — all PRs target the base branch (`develop` by default)
- Commit messages must follow `conventional-commit-message` sub-skill format
- Never mention Claude or add co-author lines in commit messages
- Every PR must reference the issue it closes (`Closes #N`)
