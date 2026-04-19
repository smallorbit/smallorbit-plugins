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

The lead agent orchestrates the team for the entire run. It does not fire-and-forget — it stays active from initial fetch through teardown, spawning a fixed pool of teammates upfront and then reading teammate status via the Agent Teams mailbox to monitor for crashes and stuck tasks. Builders self-claim additional work from the shared task list as upstream issues unblock, so the lead does not dispatch new teammates in response to completion events.

### API reference

The Agent Teams API is built from existing Claude Code primitives — there is no separate "spawn teammate" tool. Use this mapping when reading the steps below:

| Concept | Real API call |
|---|---|
| Create the team | `TeamCreate({name: "<team-name>"})` — auto-registers the calling session as `team-lead@<team-name>` |
| Spawn the reviewer | `Agent({name: "reviewer", team_name: "<team-name>", subagent_type: "general-purpose", prompt: "..."})` |
| Spawn a builder | `Agent({name: "builder-<issue>", team_name: "<team-name>", isolation: "worktree", subagent_type: "general-purpose", prompt: "..."})` |
| Send a message | `SendMessage({to: "<teammate-name>", message: "..."})` |
| Shut down a teammate | `SendMessage({to: "<teammate-name>", message: {type: "shutdown_request"}})` |
| Receive messages | Automatic — messages from teammates are delivered into the conversation; there is no `ReceiveMessage` poll |

Notes:

- **`TeamCreate` registers the orchestrator as `team-lead`**, not `lead`. Always address the orchestrator with `SendMessage({to: "team-lead", ...})`.
- **`isolation: "worktree"` on the `Agent` tool is what gives the builder its isolated git worktree.** Builders must be spawned with this flag; the reviewer must not (it audits inside the builders' worktrees, not its own). Today's in-process Agent Teams backend silently ignores the flag — see #362 — so the builder contract includes a manual-worktree fallback (see Builder Teammate Contract, step 2). Once the backend honors `isolation: "worktree"`, the fallback is a no-op.
- **Only actual squad members join the team.** The reviewer and the builders use `team_name`. Any utility/research subagents the lead spawns for its own work (codebase exploration, etc.) must be plain `Agent({...})` calls **without** `team_name` — otherwise they pollute the team mailbox.

### 1. Initial fetch

Before spawning anyone, the lead builds a starting batch of issues using swarmkit sub-skills:

- `swarmkit:gh-fetch-issues` — pull the open issue list, honoring label filters and the on-hold exclusion
- `swarmkit:issue-rank` — order the list by priority, specificity, architectural impact, and testability

The ranked list becomes the **target set**. Dependency edges between issues (e.g. stacked downstream work) are preserved so the lead can tell which issues are currently unblocked.

### 2. Spawn phase

Once the target set is known, the lead spawns a **fixed pool of teammates upfront** — one reviewer plus one builder per initially-unblocked issue. No additional teammates are spawned later in the run; instead, builders self-claim downstream issues from the shared task list as those issues unblock (see Builder Teammate Contract).

1. Spawn the reviewer **once** at the start of the run. Only one reviewer exists for the lifetime of the team:

   ```
   Agent({
     name: "reviewer",
     team_name: "<team-name>",
     subagent_type: "general-purpose",
     prompt: "<reviewer contract from the Reviewer Teammate Contract section>"
   })
   ```

2. For every initially-unblocked issue in the target set, spawn a builder named `builder-<issue>` — all at once, not staggered. The `isolation: "worktree"` flag is what gives the builder its isolated git worktree:

   ```
   Agent({
     name: "builder-<issue>",
     team_name: "<team-name>",
     isolation: "worktree",
     subagent_type: "general-purpose",
     prompt: "<builder contract from the Builder Teammate Contract section, parameterized with the issue>"
   })
   ```

The pool size equals the number of initially-unblocked issues. Blocked issues remain on the shared task list and are picked up by whichever builder finishes first and finds them unblocked — the lead does not spawn additional builders when downstream issues unblock.

### 3. Watch phase

The lead blocks on its mailbox in a **monitoring-only** role. It does not dispatch new builders in response to completion events — builders self-claim the next unblocked task (see Builder Teammate Contract), so the lead's only job during watch is to detect failure.

The lead reacts to:

- **Teammate crashes or unresponsive mailboxes** — fall through to Halt and Report
- **Mailbox delivery failures** (send returns error after N retries) — fall through to Halt and Report
- **Stuck task list** — all spawned builders have exited but unclaimed tasks remain on the shared list — log the stuck tasks and fall through to Halt and Report

Completion messages (`<issue> completed, PR: <url>`) are logged for the final summary but do **not** trigger any spawn action. The lead exits the watch phase once every spawned builder has exited and the shared task list has drained, then proceeds to mode-specific termination.

The lead reads teammate status by handling incoming messages from teammates — they are delivered automatically into the lead's conversation, so there is no `ReceiveMessage` poll. The lead does **not** probe teammates directly; all coordination flows through messages.

### 4. Mode-specific termination

- **One-shot mode** — exits as soon as every issue in the initial target set has a PR. No re-fetching.
- **Loop mode** — after the current target set drains, the lead re-runs `swarmkit:gh-fetch-issues` + `swarmkit:issue-rank` and repeats the dispatch cycle. It exits only when the board is clear (no open, non-on-hold issues match the filter).

### 5. Lead stays active

The lead never backgrounds itself. It remains the single coordinator for the entire run — spawning the initial teammate pool, watching the mailbox for crashes, and handling mode-specific termination — until teardown (issues #277, #278).

---

## Builder Teammate Contract

A builder is a teammate responsible for shipping one or more issues. It is spawned by the lead as `builder-<issue>` for an initially-unblocked issue and, after finishing, self-claims the next unblocked unassigned task from the shared list. The builder exits only when no claimable work remains.

### Workflow

1. **Claim the assigned issue** on the Agent Teams shared task list. The claim is atomic — if another teammate has already claimed this issue, abort.

2. **Worktree setup** — detect whether `isolation: "worktree"` actually took effect, then either use the pre-created worktree or fall back to manual setup:

   - **Isolation probe.** Compare `--git-dir` and `--git-common-dir`. Inside a linked worktree, `--git-dir` points at `.git/worktrees/<name>` while `--git-common-dir` points at the main repo's `.git`. Equal paths ⇒ not in a linked worktree:
     ```bash
     if [[ "$(git rev-parse --git-common-dir 2>/dev/null)" == "$(git rev-parse --git-dir 2>/dev/null)" ]]; then
       IN_WORKTREE=0
     else
       IN_WORKTREE=1
     fi
     ```

   - **Isolation took effect (`IN_WORKTREE=1`).** Create the agent branch inside the pre-created worktree, identical to `swarmkit:swarm`:
     - Independent issues branch from `develop`:
       ```bash
       git checkout -b worktree-agent-<issue> origin/develop
       ```
     - Downstream issues branch from their upstream's agent branch:
       ```bash
       git checkout -b worktree-agent-<issue> origin/worktree-agent-<upstream-issue>
       ```

   - **Isolation was ignored (`IN_WORKTREE=0`) — manual fallback.** TEMPORARY: remove once the Agent Teams backend honors `isolation: "worktree"`. See #362. The in-process backend silently drops the flag, leaving the builder in the orchestrator's cwd (the main checkout). Create the worktree explicitly, then `cd` into it before proceeding:
     ```bash
     # --- BEGIN manual-worktree fallback (remove when #362 is fixed) ---
     WORKTREE_ROOT=$(git rev-parse --show-toplevel)/.claude/worktrees
     mkdir -p "$WORKTREE_ROOT" || {
       SendMessage({to: "team-lead", message: "builder-<issue> dead-on-arrival: cannot create worktree root under .claude/worktrees/. Respawn under a new name."})
       echo "ERROR: Failed to create $WORKTREE_ROOT. Aborting."
       exit 1
     }
     # Independent issue: branch from origin/<base> (typically origin/develop)
     # Downstream issue: branch from origin/worktree-agent-<upstream-issue> instead
     git worktree add -b worktree-agent-<issue> "$WORKTREE_ROOT/worktree-agent-<issue>" origin/<base> || {
       SendMessage({to: "team-lead", message: "builder-<issue> dead-on-arrival: git worktree add failed. Respawn under a new name."})
       echo "ERROR: git worktree add failed. Aborting."
       exit 1
     }
     cd "$WORKTREE_ROOT/worktree-agent-<issue>"
     # Branch is created by `git worktree add -b`, so skip the separate `git checkout -b` step above.
     # --- END manual-worktree fallback ---
     ```

   - **Neither path succeeded — dead-on-arrival.** If the fallback itself fails (e.g. git unavailable, permission error, `git worktree add` fails), notify the lead so it can respawn under a new name rather than waiting for an audit request that will never arrive, then exit:
     ```
     SendMessage({to: "team-lead", message: "builder-<issue> dead-on-arrival: unable to establish isolated worktree. Respawn under a new name."})
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
   - Create the PR targeting the correct base (`develop` for independent issues, `worktree-agent-<upstream>` for stacked) with a richer body synthesized from the issue spec and your diff:

     ```bash
     gh pr create --base <base> --head <head> \
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

     The `<...>` placeholders are instructions, not literal text — replace each with content you derive from the issue spec and your diff. Do not copy the placeholder strings into the PR body.

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
     SendMessage({to: "team-lead", message: "<issue> completed, PR: <url>"})
     ```

8. **Self-claim the next unblocked task.** After notifying the lead, do not exit — check the shared task list for more work:

   - Call `TaskList` and scan for an issue that is unblocked and unassigned
   - Atomically claim it (same mechanism as step 1). If another teammate beat you to the claim, re-scan the list and try the next candidate
   - On a successful claim, **repeat from step 2** using the newly claimed issue as the current one (new worktree, new implementation, new review cycle, new notify)
   - If no unblocked, unassigned tasks remain, exit cleanly

   The lead does not spawn a replacement when you exit — the fixed pool drains naturally as each builder runs out of claimable work.

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

1. **Wait for an audit request.** Audit requests from builders are delivered into the conversation automatically — no polling primitive is required.

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

### Dead-on-arrival (DOA) failure mode

A builder can fail to start at all — for example, when the tmux shell is misconfigured. The failure signature looks like:

```
tmux/.tmux.conf:4: not a suitable shell
```

A builder can also fail its worktree setup step (see Builder Teammate Contract, step 2). Note that squad's DOA path here differs from `swarmkit:swarm`'s: under team-mode `Agent` spawns, `$PWD` does not reliably track the worktree path, so the builder uses a git-based probe (`git rev-parse --git-dir` vs. `--git-common-dir`) to decide whether `isolation: "worktree"` took effect. If it did not (the in-process Agent Teams backend silently ignores the flag today — see #362), the builder falls back to creating its own worktree under `<repo>/.claude/worktrees/`; DOA only fires when **both** isolation and manual setup fail (e.g. git unavailable, permission error).

When this happens the builder process exits immediately without ever joining the team mailbox. Its `isActive` flag in the team config file (`~/.claude/teams/<team>/config.json`) remains `true` because no graceful shutdown message was exchanged. Any subsequent `TeamDelete` call will be blocked with:

```
Cannot cleanup team with N active member(s): <name>. Use requestShutdown to gracefully terminate teammates first.
```

**Manual recovery path:**

1. Open `~/.claude/teams/<team>/config.json` in an editor (or use `jq`/`sed`) and set `isActive` to `false` on the dead member:
   ```bash
   # Using jq (writes to a temp file then replaces):
   jq '(.members[] | select(.name == "<name>")).isActive = false' \
     ~/.claude/teams/<team>/config.json > /tmp/team-config.json \
     && mv /tmp/team-config.json ~/.claude/teams/<team>/config.json
   ```
2. Re-run `TeamDelete` — it will now find no active members and succeed.
3. If re-running the squad, spawn the replacement builder under a **new name** (e.g. `builder-<issue>-b`) so the stale entry does not conflict.

### Explicit non-goals for v1

- No auto-respawn of crashed teammates (deferred to v2)
- No partial-success continuation — one crash halts entire run
- No automatic cleanup on halt — teardown runs but in-flight worktrees may contain uncommitted work the user should inspect first

---

## Teardown

Runs **regardless of success or halt**. Every step must be idempotent — running teardown twice must not error or leave the repo in a worse state.

### Steps (in order)

1. **Shut down teammates cleanly** — iterate the team roster and send a `shutdown_request` to each teammate via `SendMessage` (builders first, then reviewer). The teammate is responsible for replying with a `shutdown_response` and then terminating:

   ```
   SendMessage({to: "builder-<issue>", message: {type: "shutdown_request"}})   // repeat for each builder
   SendMessage({to: "reviewer", message: {type: "shutdown_request"}})
   ```

   If a teammate is already gone (crashed or already exited), the send is a no-op.

2. **Force-clear stuck `isActive` members, then delete the team** — wait a reasonable timeout (e.g. 10 seconds) for each teammate to acknowledge the shutdown. Any member whose mailbox never responds within the timeout is considered dead-on-arrival: forcibly patch `~/.claude/teams/<team>/config.json` to set its `isActive` flag to `false` so that `TeamDelete` is not blocked:

   ```bash
   # For each non-responding member <name>:
   jq '(.members[] | select(.name == "<name>")).isActive = false' \
     ~/.claude/teams/<team>/config.json > /tmp/team-config.json \
     && mv /tmp/team-config.json ~/.claude/teams/<team>/config.json
   ```

   After all stuck members are cleared, delete the team:

   ```
   TeamDelete({name: "<team-name>"})
   ```

   This step must be idempotent — if the team was already deleted (e.g. teardown is running a second time), the `TeamDelete` call should be treated as a no-op.

3. **Invoke `clean-worktrees` sub-skill** — reuses existing logic to remove all `worktree-agent-*` worktrees, delete orphan local branches, and restore the caller's branch:

   ```
   swarmkit:clean-worktrees
   ```

4. **Unset scoped git config** — unset `claude.prBase` if it was set for this operation (mirrors `swarmkit:swarm` loop-mode teardown):

   ```bash
   git config --unset claude.prBase 2>/dev/null || true
   ```

5. **Final summary** — print what ran, which PRs are open for review, and any in-flight work needing manual inspection (in halt case):

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
