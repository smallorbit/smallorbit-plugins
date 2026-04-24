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
- `--builders <N>` → cap the builder pool size (default: `5`)

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

Used when explicit issue numbers are provided. Dispatches Agent Teams builders for the given set of issues, opens PRs via the builder/reviewer workflow, and reports results.

### 1. Build the target set

For each issue number parsed from `$ARGUMENTS`:

```bash
gh issue view <number> --json title,body,labels
```

**Skip any issue with the `on-hold` label.**

**Epic expansion** — query each issue's children via the sub-issue API:

```bash
gh api repos/{owner}/{repo}/issues/<number>/sub_issues
```

If the response is a non-empty array, the issue is an epic. Use the children (not the epic itself) as work items: fetch `title,body,labels,state` for each child in parallel, then filter:

- Skip any child with the `on-hold` label
- Skip any child that is already `closed`

If all children are skipped, announce and stop. Otherwise announce:

> `#N` is an epic. Dispatching: `#101`, `#102`. Skipped (closed/on-hold): `#103`.

**Epic label without sub-issues** — if the issue carries the `epic` label but the sub-issues API returns an empty array, the epic is not wired up. Do **not** treat it as a regular implementation issue. Announce and skip:

> `#N` is labeled `epic` but has no sub-issues wired via the GitHub sub-issue API. Skipping — children must be attached via `gh api .../sub_issues` before dispatching.

### 2. Parse dependency graph

For each issue body fetched in Step 1, extract `Depends on #N` and `Blocked by #N` references:

```bash
echo "$BODY" | grep -oiE '(depends on|blocked by) #[0-9]+' | grep -oE '[0-9]+'
```

Build a directed acyclic graph (DAG): each issue is a node; a `Depends on #N` or `Blocked by #N` relationship is a directed edge from the dependent to the dependency.

Produce a **topological sort** of the DAG:
- **Unblocked issues**: no incoming edges within this batch — spawn builders in parallel
- **Blocked issues**: have upstream dependencies that must complete first — added to the shared TaskList with `blockedBy` metadata

### 3. Populate the shared TaskList

Add one task per issue to the Agent Teams shared TaskList:

- `id`: the issue number
- `title`: the issue title
- `body`: the issue body (acceptance criteria)
- `status`: `unblocked` or `blocked`
- `blockedBy`: list of upstream issue numbers (empty for independent issues)
- `assignee`: `null` (builders self-claim)

Blocked tasks transition to `unblocked` when all their `blockedBy` dependencies report completion. Builders check the TaskList for claimable work after finishing each issue (see Builder Teammate Contract, step 9).

### 4. Apply `status:in-progress` label

Ensure the label exists, then apply it to every issue in the target set:

```bash
gh label list | grep -q "status:in-progress" || \
  gh label create "status:in-progress" --description "Actively being worked on" --color "E4E669"
```

For each issue number in the target set:

```bash
gh issue edit <issue> --add-label "status:in-progress"
```

### 5. Present dispatch plan

Before spawning any teammates, print a summary table of builder assignments so the operator has a clear view of what is about to run. Proceed immediately — no approval gate.

```
| Builder | Issue(s) | Branch | Model | Notes |
|---------|----------|--------|-------|-------|
| builder-16 | #16 | worktree-agent-16 | sonnet | Independent |
| builder-18 | #18 | worktree-agent-18 | opus | Blocked by #16 |
```

Include:
- **Suggested merge order** — leaf PRs first (no dependents), root PRs last
- **Any issues too ambiguous to delegate** — list them with a brief reason; they are excluded from the dispatch but not from the target set

After printing the table, continue immediately to the next step.

### 6. Create team and spawn teammates

Create the team:

```
TeamCreate({name: "squad-<run-id>"})
```

Spawn the reviewer **once**:

```
Agent({
  name: "reviewer",
  team_name: "squad-<run-id>",
  subagent_type: "general-purpose",
  prompt: "<reviewer contract from the Reviewer Teammate Contract section>"
})
```

Determine the optimal builder pool size, then spawn that many builders — each assigned one of the initially-unblocked issues. Remaining unblocked issues stay on the TaskList for builders to self-claim as they finish.

**Pool sizing** — the pool size is `min(parallel_lanes, max_builders)`:

- **`parallel_lanes`**: the number of initially-unblocked issues that have no file overlap with each other. Two issues overlap if their specs reference the same file. Issues in the same dependency chain are already serialized by the DAG — this check catches independent issues that would still conflict.
- **`max_builders`**: defaults to `5`. Can be overridden via `--builders N` in `$ARGUMENTS`.

If `parallel_lanes` is 0 (all issues are blocked), spawn 1 builder for the first issue that will unblock.

Spawn all builders at once, not staggered:

```
Agent({
  name: "builder-<issue>",
  team_name: "squad-<run-id>",
  isolation: "worktree",
  subagent_type: "general-purpose",
  prompt: "<builder contract from the Builder Teammate Contract section, parameterized with the issue>"
})
```

Builders self-claim the next unblocked task from the TaskList when they finish (see Builder Teammate Contract, step 9), so a pool smaller than the unblocked count still processes every issue — it just takes more rounds.

### 7. Monitor and exit

Enter the Dispatch Loop (watch phase). The lead monitors the mailbox for completion messages and crash signals.

Exit when every issue in the initial target set has a PR (or has halted). No re-fetching — one-shot mode processes only the explicitly requested issues. Proceed to Halt and Report (on failure) or Teardown (on success).

---

## Loop Mode

Used when no issue numbers are given (no args or label filter). Continuously clears the board using Agent Teams.

### Setup

```bash
git fetch origin
```

Set `claude.flowkit.prBase` to scope the PR base for this operation:

```bash
git config --local claude.flowkit.prBase $BASE
```

This is unset during teardown. Leaving it set will cause subsequent PR creation to target the wrong base.

### Loop (repeat until board clear or unrecoverable failure)

**Step 1 — Seed the target set**

Follow `swarmkit:gh-fetch-issues` to fetch open issues (apply label filter if given), then follow `swarmkit:issue-rank` to rank and select all issues that can safely parallelize this cycle.

If no open issues remain, announce "Board is clear" and exit.

**Step 2 — Parse dependencies and populate TaskList**

For each issue body, extract `Depends on #N` and `Blocked by #N` references:

```bash
echo "$BODY" | grep -oiE '(depends on|blocked by) #[0-9]+' | grep -oE '[0-9]+'
```

Build the DAG, topological sort, and populate the shared TaskList with one task per issue (same structure as One-Shot Mode, step 3) — `id`, `title`, `body`, `status` (`unblocked`/`blocked`), `blockedBy`, and `assignee`.

**Step 3 — Apply `status:in-progress` label**

Ensure the label exists, then apply it to every issue in the target set:

```bash
gh label list | grep -q "status:in-progress" || \
  gh label create "status:in-progress" --description "Actively being worked on" --color "E4E669"
```

For each issue number in the target set:

```bash
gh issue edit <issue> --add-label "status:in-progress"
```

**Step 4 — Create team and spawn**

Before spawning, print the dispatch plan table (same format as One-Shot Mode step 5: Builder / Issue(s) / Branch / Model / Notes, with suggested merge order). Proceed immediately — no approval gate.

Create the team (once per loop-mode run, reused across cycles):

```
TeamCreate({name: "squad-<run-id>"})
```

Spawn the reviewer **once** at the start of the first cycle. It persists across all cycles — do not respawn between batches.

Determine the builder pool size using the same formula as One-Shot Mode step 4: `min(parallel_lanes, max_builders)`. Spawn that many builders, each assigned one initially-unblocked issue. Remaining unblocked issues stay on the TaskList for self-claim.

**Builder naming in loop mode** — use a cycle-scoped suffix `builder-<issue>-c<cycle>` (where `<cycle>` starts at 1 and increments each time the board is re-seeded). This avoids roster collisions with stale entries from previous cycles: the Agent Teams config retains member records across cycles, so reusing a name like `builder-42` on cycle 2 would conflict with the cycle-1 entry that never received a clean shutdown.

```
Agent({
  name: "builder-<issue>-c<cycle>",
  team_name: "squad-<run-id>",
  isolation: "worktree",
  subagent_type: "general-purpose",
  prompt: "<builder contract from the Builder Teammate Contract section, parameterized with the issue>"
})
```

Builders self-claim downstream tasks from the TaskList as they unblock (see Builder Teammate Contract, step 9). Between cycles, top up the pool if builders have exited and new unblocked issues exist — but never exceed `max_builders` active builders at once.

**Step 5 — Monitor current batch**

Enter the Dispatch Loop (watch phase). The lead monitors the mailbox for completion messages and crash signals. The batch is drained when every spawned builder has exited and no claimable tasks remain on the TaskList.

**Step 6 — Checkpoint**

```
── Cycle N complete ──────────────────────────
PRs opened: #25 (→ #12), #26 (→ #15)
Failed: #14 (builder crash, no PR produced)
Blocked: #20 (depends on #14)
Remaining open issues: 5
──────────────────────────────────────────────
```

**Step 7 — Re-fetch and re-seed**

After the current batch drains, increment the cycle counter, re-run `swarmkit:gh-fetch-issues` + `swarmkit:issue-rank` to discover newly-opened or previously-blocked issues. If the re-fetch returns issues, populate a fresh TaskList and spawn new builders for the next cycle's unblocked issues using the updated `c<cycle>` suffix (the reviewer persists — do not respawn it).

Repeat from Step 1 until:
- The board is clear (no open, non-on-hold issues match the filter) — proceed to Teardown
- An unrecoverable failure occurs (builder crash with no PR, base branch corrupted) — proceed to Halt and Report

### Smart failure rules

When an issue fails at any point:
1. Check all remaining issues in current and future cycles for dependency references to the failed issue
2. Mark those as blocked on the TaskList; continue with all unblocked issues
3. Report blocked issues at each checkpoint

**Unrecoverable failures** (exit loop immediately):
- Builder produced no PR (crash, timeout, no push)
- `$BASE` branch deleted or corrupted externally

---

## Dispatch Loop

The lead agent orchestrates the team for the entire run. It does not fire-and-forget — it stays active from initial fetch through teardown, spawning a fixed pool of teammates upfront and then reading teammate status via the Agent Teams mailbox to monitor for crashes and stuck tasks. Builders self-claim additional work from the shared task list as upstream issues unblock, so the lead does not dispatch new teammates in response to completion events.

**Mode entry points differ:** Loop mode enters at step 1 (Initial fetch) to build the target set from scratch. One-shot mode skips steps 1–2 entirely — it enters the Dispatch Loop at step 3 (Watch phase) with the target set and TaskList already populated from One-Shot steps 1–4.

### API reference

The Agent Teams API is built from existing Claude Code primitives — there is no separate "spawn teammate" tool. Use this mapping when reading the steps below:

| Concept | Real API call |
|---|---|
| Create the team | `TeamCreate({name: "<team-name>"})` — auto-registers the calling session as `team-lead@<team-name>` |
| Spawn the reviewer | `Agent({name: "reviewer", team_name: "<team-name>", subagent_type: "general-purpose", prompt: "..."})` |
| Spawn a builder | `Agent({name: "builder-<issue>" (one-shot) or "builder-<issue>-c<cycle>" (loop), team_name: "<team-name>", isolation: "worktree", subagent_type: "general-purpose", prompt: "..."})` |
| Send a message | `SendMessage({to: "<teammate-name>", message: "..."})` |
| Shut down a teammate | `SendMessage({to: "<teammate-name>", message: {type: "shutdown_request"}})` |
| Receive messages | Automatic — messages from teammates are delivered into the conversation; there is no `ReceiveMessage` poll |

Notes:

- **`TeamCreate` registers the orchestrator as `team-lead`**, not `lead`. Always address the orchestrator with `SendMessage({to: "team-lead", ...})`.
- **`isolation: "worktree"` on the `Agent` tool is what gives the builder its isolated git worktree.** Builders must be spawned with this flag; the reviewer must not (it audits inside the builders' worktrees, not its own). Today's in-process Agent Teams backend silently ignores the flag — see #362 — so the builder contract includes a manual-worktree fallback (see Builder Teammate Contract, step 3). Once the backend honors `isolation: "worktree"`, the fallback is a no-op.
- **Only actual squad members join the team.** The reviewer and the builders use `team_name`. Any utility/research subagents the lead spawns for its own work (codebase exploration, etc.) must be plain `Agent({...})` calls **without** `team_name` — otherwise they pollute the team mailbox.

### 1. Initial fetch _(loop mode only)_

Before spawning anyone, the lead builds a starting batch of issues using swarmkit sub-skills:

- `swarmkit:gh-fetch-issues` — pull the open issue list, honoring label filters and the on-hold exclusion
- `swarmkit:issue-rank` — order the list by priority, specificity, architectural impact, and testability

The ranked list becomes the **target set**. Dependency edges between issues (e.g. stacked downstream work) are preserved so the lead can tell which issues are currently unblocked.

### 2. Spawn phase

Once the target set is known, the lead spawns a **capped pool of teammates** — one reviewer plus a number of builders determined by the pool-sizing formula from One-Shot Mode step 4: `min(parallel_lanes, max_builders)`. Builders self-claim downstream issues from the shared task list as those issues unblock (see Builder Teammate Contract), so the pool does not need to match the issue count 1:1.

1. Spawn the reviewer **once** at the start of the run. Only one reviewer exists for the lifetime of the team:

   ```
   Agent({
     name: "reviewer",
     team_name: "<team-name>",
     subagent_type: "general-purpose",
     prompt: "<reviewer contract from the Reviewer Teammate Contract section>"
   })
   ```

2. Spawn builders up to the pool cap, each assigned one initially-unblocked issue — all at once, not staggered. The `isolation: "worktree"` flag is what gives the builder its isolated git worktree:

   ```
   Agent({
     name: "builder-<issue>",          // one-shot mode
     name: "builder-<issue>-c<cycle>", // loop mode — cycle suffix prevents roster collisions across re-seeds
     team_name: "<team-name>",
     isolation: "worktree",
     subagent_type: "general-purpose",
     prompt: "<builder contract from the Builder Teammate Contract section, parameterized with the issue>"
   })
   ```

Remaining unblocked issues stay on the shared task list and are picked up by whichever builder finishes first. The lead does not spawn additional builders when downstream issues unblock — the pool drains naturally as builders self-claim and complete work.

### 3. Watch phase

The lead blocks on its mailbox in a **monitoring-only** role. It does not dispatch new builders in response to completion events — builders self-claim the next unblocked task (see Builder Teammate Contract), so the lead's only job during watch is to detect failure.

The lead reacts to:

- **Teammate crashes or unresponsive mailboxes** — fall through to Halt and Report
- **Mailbox delivery failures** (send returns error after N retries) — fall through to Halt and Report
- **Stuck task list** — all spawned builders have exited but unclaimed tasks remain on the shared list — log the stuck tasks and fall through to Halt and Report

Completion messages (`<issue> completed, PR: <url>`) are logged for the final summary but do **not** trigger any spawn action. The lead exits the watch phase once every spawned builder has exited and the shared task list has drained, then proceeds to mode-specific termination.

The lead reads teammate status by handling incoming messages from teammates — they are delivered automatically into the lead's conversation, so there is no `ReceiveMessage` poll. The lead does **not** probe teammates directly; all coordination flows through messages.

#### 3a. Post-roundtrip transcript-size poll

After **every** `SendMessage` roundtrip with a named teammate (i.e. every time the lead sends a message to a teammate and receives a reply, or otherwise completes an exchange with a named teammate during watch), the lead performs a lightweight transcript-size check to detect teammate context exhaustion before it crashes the teammate. The check piggybacks on Dispatch Loop iteration — **there is no periodic timer; time-based polling is explicitly out of scope for v1**.

Declare the threshold as a named constant:

```
ROTATE_THRESHOLD_BYTES = 1048576   # 1.0 MB
```

**Rationale (from empirical probe #452):** a teammate transcript on disk grows roughly from ~300 KB when fresh to ~1.4 MB when the session has exhausted its context window. 1.0 MB is the conservative midpoint — large enough to avoid churning handoffs on healthy sessions, small enough to fire well before the teammate actually crashes. **Making this threshold configurable is out of scope for v1** — it is hard-coded deliberately until real-world data justifies a knob.

For each roundtrip with teammate `<name>`, run these three steps **in order**:

1. **Look up the session UUID** for `<name>` in the `teammate_hello` cache (see the Teammate Hello section, lead-side handling). If the cache has no entry for `<name>` — or the cached `session_uuid` is `null` — skip the check for this roundtrip and log the gap. The hello handshake may not have been processed yet, or resolution failed on the teammate side; either way, there is nothing to `stat`.

2. **`stat` the transcript file** at `~/.claude/projects/<slug>/<uuid>.jsonl`, where `<slug>` is derived from the current working directory the same way the teammate derives it for `teammate_hello` — by replacing every `/` with `-`:

   ```bash
   SLUG=$(pwd | sed 's|/|-|g')
   SIZE=$(stat -f %z ~/.claude/projects/"$SLUG"/"$UUID".jsonl 2>/dev/null || stat -c %s ~/.claude/projects/"$SLUG"/"$UUID".jsonl 2>/dev/null)
   ```

   If the file does not exist or `stat` fails, skip the check for this roundtrip and log the gap — do not error out.

3. **Emit `request_handoff` if size ≥ `ROTATE_THRESHOLD_BYTES`.** Send the `request_handoff` message (schema defined in the Preemptive Handoff section) to `<name>`:

   ```
   SendMessage({
     to: "<name>",
     message: { type: "request_handoff", ... }
   })
   ```

   The handoff dialogue itself — the teammate's `handoff_ready` reply, successor spawn, and teardown cleanup — is specified in separate issues (#514–#517) and is not part of this check. The check's sole responsibility is **detecting the threshold breach and emitting `request_handoff`**.

Do not re-emit `request_handoff` to the same teammate while an earlier one for that teammate is still outstanding — one handoff request per teammate at a time.

#### 3b. Successor spawn on `handoff_ready` receipt

When the lead receives a `handoff_ready` message (schema in the Preemptive Handoff Messages section) from a retiring teammate, it spawns a fresh successor that resumes the predecessor's in-flight work. This is the step that keeps headcount stable — without it, every preemptive handoff permanently reduces the pool by one and the squad eventually starves.

On receipt of `handoff_ready` from predecessor `<predecessor>` carrying `current_task_id` and a role-specific `state` blob, the lead spawns the successor immediately — before clearing the outstanding `request_handoff` entry for `<predecessor>`.

##### Successor name: `<role>-h<N>` lineage counter

The successor's `Agent({name: ...})` is derived by appending (or incrementing) a `-h<N>` suffix on the predecessor's name:

| Predecessor name | Successor name |
|---|---|
| `reviewer` | `reviewer-h1` |
| `reviewer-h1` | `reviewer-h2` |
| `builder-42` | `builder-42-h1` |
| `builder-42-c2` | `builder-42-c2-h1` |
| `builder-42-h1` | `builder-42-h2` |
| `builder-42-h2` | `builder-42-h3` |

**Counter rules:**

- The counter `N` is **per-lineage**, not per-cycle: every successor in the same chain increments from the last `-h<N>` on the predecessor's name. A chain may grow arbitrarily long (`builder-42` → `-h1` → `-h2` → `-h3` → ...) within a single run.
- **The counter spans chains** — it is not reset by loop-mode cycle boundaries, by reviewer handoffs, or by unrelated builder handoffs. As long as a teammate is the handoff descendant of another, the counter continues climbing on that lineage.
- The counter is derived mechanically from the predecessor's name — parse the trailing `-h<digits>` if present, increment it; otherwise append `-h1`. The lead does not maintain a separate counter store; the name itself is the source of truth.
- Names from other axes (`-c<cycle>` loop suffix, issue numbers) are preserved verbatim; only the `-h<N>` segment moves.

##### Spawn options: no `isolation: "worktree"`

The successor is spawned via `Agent({...})` with the **same** `team_name`, `subagent_type`, and general spawn shape as the predecessor, with one critical exception:

> **Do not pass `isolation: "worktree"` on the successor spawn.** The predecessor's `handoff_ready` payload carries the `worktree_path` (builder variant) where the in-flight work — including any `stash_ref` — lives. A fresh isolated worktree would orphan the stash: the successor would land in a brand-new empty working tree with no path back to the predecessor's stashed edits or branch. Reusing the predecessor's worktree is what makes the stash-pop and branch continuity possible.

For reviewers the flag is already omitted (reviewers never spawn with `isolation: "worktree"` in the first place), so the rule is a no-op on that side; it is stated here for consistency so the spawn shape matches across roles.

##### Spawn prompt

The successor's prompt is the same role contract (Builder Teammate Contract or Reviewer Teammate Contract) as the predecessor, **prefixed** with a handoff-resume preamble derived from the `handoff_ready` payload:

1. **`cd` into the predecessor's worktree.** For the builder variant, use `state.worktree_path` verbatim. For the reviewer variant, the `state` blob is empty and no `cd` is needed — the reviewer is stateless on the filesystem.

   ```bash
   cd <state.worktree_path>        # builder only
   ```

2. **`git stash pop <stash_ref>` — builders only, and only if `state.stash_ref` is non-null.** The reviewer has no stash (its `state` is empty), so no pop is performed. If the builder's predecessor committed everything before quiescing and `state.stash_ref` is null, skip the pop.

   ```bash
   git stash pop <state.stash_ref>   # builder only, only when stash_ref != null
   ```

3. **Re-claim the task.** The preamble includes `current_task_id` from the payload so the successor can atomically re-claim it on the shared task list (the predecessor released the claim as part of its quiesce sequence — see Builder Teammate Contract step 10 and Reviewer Teammate Contract step 8). The successor then resumes the role's normal workflow from the appropriate step (builder: implementation; reviewer: audit loop).

After spawning, the lead clears the outstanding-handoff tracking entry for `<predecessor>` so a future transcript-size breach against the successor can issue its own `request_handoff`. Predecessor teardown (removing the stale name from the team config, verifying it has exited) is out of scope here and handled separately.

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

2. **Self-report session UUID to the lead.** As the FIRST outbound message after spawn (before worktree setup, before any other coordination), resolve the session UUID and send a `teammate_hello` payload to the lead. See the Teammate Hello section for the schema and resolution steps:

   ```bash
   SLUG=$(pwd | sed 's|/|-|g')
   SESSION_UUID=$(ls -t ~/.claude/projects/"$SLUG"/*.jsonl 2>/dev/null | head -n1 | xargs -n1 basename | sed 's/\.jsonl$//')
   ```

   Then:

   ```
   SendMessage({
     to: "team-lead",
     message: {
       type: "teammate_hello",
       role: "builder",
       name: "builder-<issue>",           // or "builder-<issue>-c<cycle>" in loop mode
       session_uuid: "<resolved-uuid>"
     }
   })
   ```

   The lead caches this mapping (see Teammate Hello, lead-side handling) before any further coordination happens.

3. **Worktree setup** — detect whether `isolation: "worktree"` actually took effect, then either use the pre-created worktree or fall back to manual setup:

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

4. **Implement the issue changes.** Use relative paths only from CWD. Stay scoped to the issue's acceptance criteria.

5. **Request review** by sending the reviewer the issue number and the diff path, then wait for a response:

   ```
   SendMessage({to: "reviewer", message: "<issue>#<diff-path>"})
   ```

   Block on the mailbox until the reviewer replies with `approve` or `revise: <reasons>`.

6. **On `approve`**:
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

7. **On `revise: <reasons>`**:
   - Address the feedback
   - Re-request review (repeat step 5)
   - Repeat until the reviewer responds `approve`

8. **Notify**:
   - After a successful push, notify any downstream builder so they can rebase onto the updated upstream:
     ```
     SendMessage({to: "builder-<downstream>", message: "pushed"})
     ```
   - Report completion to the lead:
     ```
     SendMessage({to: "team-lead", message: "<issue> completed, PR: <url>"})
     ```

9. **Self-claim the next unblocked task.** After notifying the lead, do not exit — check the shared task list for more work:

   - Call `TaskList` and scan for an issue that is unblocked and unassigned
   - Atomically claim it (same mechanism as step 1). If another teammate beat you to the claim, re-scan the list and try the next candidate
   - On a successful claim, **repeat from step 3** (worktree setup) using the newly claimed issue as the current one (new worktree, new implementation, new review cycle, new notify). Do **not** repeat step 2 — the `teammate_hello` handshake is spawn-scoped and fires only once per teammate lifetime
   - If no unblocked, unassigned tasks remain, exit cleanly

   The lead does not spawn a replacement when you exit — the fixed pool drains naturally as each builder runs out of claimable work.

10. **Handle `request_handoff` from the lead.** At any point after step 2, the lead may send a `request_handoff` message signalling that the builder should retire voluntarily so a fresh successor can resume its work (see the Preemptive Handoff section for the schema). On receipt, the builder quiesces its in-flight state, releases its claim, reports back, and exits. Perform these steps **in order** — stashing must complete before the task-list claim is released so the worktree is quiesced and stable before any successor can re-claim it:

    1. **Stash in-flight edits.** Run `git stash -u` in the current worktree to preserve both tracked and untracked uncommitted changes. Capture the resulting stash ref (typically `stash@{0}`). If the working tree is clean, there will be no stash — record `stash_ref: null` for the reply.
       ```bash
       if git stash -u --include-untracked 2>/dev/null | grep -q 'Saved working directory'; then
         STASH_REF="stash@{0}"
       else
         STASH_REF=null
       fi
       ```

    2. **Release the task-list claim.** Unassign the builder from the current issue on the Agent Teams shared task list so the successor can atomically re-claim it (same mechanism as step 1, in reverse). Until this release completes, the successor cannot claim the task and the handoff will stall.

    3. **Reply with `handoff_ready`.** Send the builder-variant payload to the lead, carrying the state blob the lead needs to spawn the successor into the same worktree:
       ```
       SendMessage({
         to: "team-lead",
         message: {
           type: "handoff_ready",
           role: "builder",
           predecessor: "builder-<issue>",       // or "builder-<issue>-c<cycle>" in loop mode
           current_task_id: "<issue>",
           state: {
             worktree_path: "<absolute path to this worktree>",
             stash_ref:     "<STASH_REF from step 10.1, or null>",
             branch:        "worktree-agent-<issue>"
           }
         }
       })
       ```

    4. **Exit cleanly.** Do not re-enter step 9's self-claim loop — the handoff is terminal for this teammate. The lead spawns the successor separately (see #516); this builder's lifetime ends here.

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

1. **Self-report session UUID to the lead.** As the FIRST outbound message after spawn (before waiting on audit requests), resolve the session UUID and send a `teammate_hello` payload to the lead. See the Teammate Hello section for the schema and resolution steps:

   ```bash
   SLUG=$(pwd | sed 's|/|-|g')
   SESSION_UUID=$(ls -t ~/.claude/projects/"$SLUG"/*.jsonl 2>/dev/null | head -n1 | xargs -n1 basename | sed 's/\.jsonl$//')
   ```

   Then:

   ```
   SendMessage({
     to: "team-lead",
     message: {
       type: "teammate_hello",
       role: "reviewer",
       name: "reviewer",
       session_uuid: "<resolved-uuid>"
     }
   })
   ```

   This fires exactly once per reviewer spawn — the reviewer is long-running across the whole team lifetime, so there is no per-audit repeat.

2. **Wait for an audit request.** Audit requests from builders are delivered into the conversation automatically — no polling primitive is required.

3. **Parse the request.** Builders send structured payloads of the form:

   ```
   {from: "builder-N", issue: "N", branch: "worktree-agent-N", diff-path: "<worktree path>"}
   ```

4. **Read the diff** directly from the builder's worktree — no filesystem writes, no `git checkout`:

   ```bash
   git -C <diff-path> diff develop...HEAD
   ```

5. **Audit against the issue spec.** Check the diff against the acceptance criteria on the referenced issue:
   - Is the scope correct? (no extra files, no unrelated refactors)
   - Any obvious bugs?
   - Are tests present where the spec calls for them?

6. **Respond** to the requesting builder:
   - Approve:
     ```
     SendMessage({to: "builder-N", message: "approve"})
     ```
   - Request revisions with concise, actionable reasons:
     ```
     SendMessage({to: "builder-N", message: "revise: <concise actionable reasons>"})
     ```

7. **Return to step 2** and serve the next audit request.

8. **Handle `request_handoff` from the lead.** At any point after step 1, the lead may send a `request_handoff` message signalling that the reviewer should retire voluntarily so a fresh successor can take over (see the Preemptive Handoff section for the schema). The reviewer handoff is strictly cheaper than the builder variant — the reviewer is stateless on the filesystem, holds no worktree, owns no stash, and carries no task-list claim — so there is nothing to quiesce. Perform these steps **in order**:

   1. **Do not drain the mailbox.** Any pending audit requests queued by builders are **left unanswered** for the successor. Draining near context exhaustion is precisely where the reviewer fails — the successor, spawned fresh, handles the unserved queue instead. Do not attempt to flush, ack, or partially process queued audits.

   2. **Reply with `handoff_ready`.** Send the reviewer-variant payload to the lead:
      ```
      SendMessage({
        to: "team-lead",
        message: {
          type: "handoff_ready",
          role: "reviewer",
          predecessor: "reviewer",
          current_task_id: null,
          state: {}
        }
      })
      ```
      `current_task_id` is `null` between audits; if the reviewer was mid-audit when `request_handoff` arrived, set it to the issue identifier from the in-flight audit request so the successor knows which builder is still waiting. The `state` blob is empty — the reviewer owns no worktree, branch, or stash.

   3. **Exit cleanly.** Do not re-enter step 2's mailbox wait — the handoff is terminal for this reviewer. The lead spawns the successor separately (see #516), and the successor inherits the undrained mailbox and responds to its queued audit requests fresh. Post-PR revision by a handed-off reviewer is explicitly out of scope.

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

A builder can also fail its worktree setup step (see Builder Teammate Contract, step 3). Note that squad's DOA path here differs from `swarmkit:swarm`'s: under team-mode `Agent` spawns, `$PWD` does not reliably track the worktree path, so the builder uses a git-based probe (`git rev-parse --git-dir` vs. `--git-common-dir`) to decide whether `isolation: "worktree"` took effect. If it did not (the in-process Agent Teams backend silently ignores the flag today — see #362), the builder falls back to creating its own worktree under `<repo>/.claude/worktrees/`; DOA only fires when **both** isolation and manual setup fail (e.g. git unavailable, permission error).

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

## Teammate Hello

Every teammate (builder or reviewer) self-reports its Claude Code session UUID to the lead as its FIRST outbound message after spawn. The lead needs this UUID to externally observe the teammate's transcript file (e.g. for context-size polling — see #513) without scanning the raw JSONL stream itself. A single inline `SendMessage` payload, `teammate_hello`, carries the report.

This section defines the `teammate_hello` schema and the lead-side cache it populates. The polling loop that consumes the cache is out of scope here and is specified in #513.

### Session UUID resolution (teammate side)

Before sending `teammate_hello`, the teammate resolves its own session UUID using the `sessionkit:get-session-id` path scheme:

- **Project slug** — derived from the current working directory by replacing every `/` with `-`:
  ```bash
  SLUG=$(pwd | sed 's|/|-|g')
  ```
- **Session UUID** — the basename (without the `.jsonl` extension) of the most-recently-modified `.jsonl` file under `~/.claude/projects/<slug>/`:
  ```bash
  SESSION_UUID=$(ls -t ~/.claude/projects/"$SLUG"/*.jsonl 2>/dev/null | head -n1 | xargs -n1 basename | sed 's/\.jsonl$//')
  ```

If the resolution yields an empty string (no project dir, no transcripts), the teammate sends `teammate_hello` with `session_uuid: null` so the lead can log the gap without crashing its cache update.

### `teammate_hello` (teammate → lead)

Sent by every teammate — builder or reviewer — as its first outbound message after spawn, before any worktree setup, audit handling, or other coordination.

**Payload shape:**

```
SendMessage({
  to: "team-lead",
  message: {
    type: "teammate_hello",
    role: "builder" | "reviewer",
    name: "<teammate-name>",
    session_uuid: "<resolved-uuid-or-null>"
  }
})
```

**Fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string literal `"teammate_hello"` | yes | Discriminator — matches the dispatcher on the lead side. |
| `role` | enum `"builder"` \| `"reviewer"` | yes | Role of the sender. The lead may use this for per-role policies (e.g. distinct polling thresholds) but does not key the cache on it. |
| `name` | string | yes | Teammate name exactly as spawned (e.g. `builder-123`, `builder-123-c2`, `reviewer`). This is the cache key. |
| `session_uuid` | string \| null | yes | Claude Code session UUID resolved via the `sessionkit:get-session-id` path scheme. `null` if resolution failed. |

**Direction:** teammate → lead (unicast to `team-lead`). Exactly one `teammate_hello` is sent per teammate spawn. It is **not** re-sent when a builder self-claims a follow-on task — self-claim stays within the same session, so the cached UUID is still valid.

### Lead-side handling

The lead maintains an in-memory **name → session_uuid** cache for the lifetime of the team. When a `teammate_hello` arrives:

1. **Key by `name`.** The cache is keyed on the `name` field — not on role or session UUID — because name is the same handle the lead uses for `SendMessage`, `shutdown_request`, and successor-spawn accounting.
2. **Overwrite on respawn.** If an entry for the incoming `name` already exists (e.g. a preemptive-handoff successor reusing the predecessor's name, or a DOA-recovery respawn), overwrite it unconditionally. The successor's session UUID cleanly replaces the predecessor's — the lead does not keep stale UUIDs around.
3. **No broadcast.** The lead does not propagate the cache to other teammates; it is consumed only by lead-side processes (e.g. transcript-size polling in #513).

The cache is discarded at teardown along with the rest of the team state.

---

## Preemptive Handoff Messages

Preemptive handoff lets a long-running teammate retire voluntarily before it crashes against its context window and hand its in-flight work to a fresh successor. Two inline `SendMessage` payloads carry the lead↔teammate dialogue: `request_handoff` (lead → teammate) initiates the handoff; `handoff_ready` (teammate → lead) returns the state blob the lead needs to spawn the successor.

This section defines the message schemas only. The polling loop that emits `request_handoff`, the teammate's handler for receiving it, and the lead's successor-spawn path are specified in separate issues (#513–#516) and must not be inferred from this section.

### `request_handoff` (lead → teammate)

Sent by the lead when it observes that a teammate's context usage has crossed a configured threshold and a preemptive handoff should begin. The recipient is a single teammate (builder or reviewer); the payload is addressed via `SendMessage({to: "<teammate-name>", ...})`.

**Payload shape:**

```
SendMessage({
  to: "<teammate-name>",
  message: {
    type: "request_handoff",
    role: "builder" | "reviewer",
    reason: "context_threshold",
    threshold_bytes: <integer>
  }
})
```

**Fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string literal `"request_handoff"` | yes | Discriminator — matches the dispatcher on the teammate side. |
| `role` | enum `"builder"` \| `"reviewer"` | yes | Role of the recipient. Echoes the teammate's role so the teammate can assert it matches its own and the lead knows which variant of `handoff_ready` to expect. |
| `reason` | enum | yes | Why the handoff was initiated. v1 defines a single value: `"context_threshold"`. Future reasons (e.g. `"manual"`, `"stuck_task"`) will extend the enum; unknown values must be rejected by the teammate. |
| `threshold_bytes` | integer | yes | Observed context-usage measurement (in bytes) that triggered the handoff. Informational — the teammate does not re-check this; the lead's decision is authoritative. |

**Direction:** lead → teammate (unicast). The lead never broadcasts `request_handoff`; one message per teammate being retired.

### `handoff_ready` (teammate → lead)

Sent by the teammate in response to `request_handoff` once it has quiesced its in-flight work (committed or stashed local edits, recorded the current task) and is ready to be replaced. The lead uses the returned state blob to spawn a successor that resumes exactly where the predecessor left off.

**Payload shape (builder variant):**

```
SendMessage({
  to: "team-lead",
  message: {
    type: "handoff_ready",
    role: "builder",
    predecessor: "<teammate-name>",
    current_task_id: "<issue-or-task-id>",
    state: {
      worktree_path: "<absolute path to the builder's worktree>",
      stash_ref:     "<git stash ref, e.g. stash@{0}, or null if nothing was stashed>",
      branch:        "<current branch name, e.g. worktree-agent-<issue>>"
    }
  }
})
```

**Payload shape (reviewer variant):**

```
SendMessage({
  to: "team-lead",
  message: {
    type: "handoff_ready",
    role: "reviewer",
    predecessor: "<teammate-name>",
    current_task_id: "<issue-or-task-id-being-reviewed, or null if idle>",
    state: {}
  }
})
```

**Common fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | string literal `"handoff_ready"` | yes | Discriminator. |
| `role` | enum `"builder"` \| `"reviewer"` | yes | Role of the sender — selects which `state` variant applies. |
| `predecessor` | string | yes | Teammate name being retired (e.g. `builder-123` or `builder-123-c2`). The lead uses this to derive the successor name and mark the predecessor for shutdown. |
| `current_task_id` | string \| null | yes | Issue or task identifier the predecessor was working on at the moment of handoff. For the reviewer this may be null if the reviewer was idle between audits. The successor resumes from this task. |
| `state` | object | yes | Role-specific resume blob — see variants below. |

**Builder `state` variant (required when `role == "builder"`):**

| Field | Type | Required | Description |
|---|---|---|---|
| `worktree_path` | string | yes | Absolute path to the builder's isolated worktree. The successor `cd`s into this path instead of creating a fresh worktree. |
| `stash_ref` | string \| null | yes | Git stash ref (e.g. `stash@{0}`) capturing any uncommitted edits the predecessor chose to preserve, or `null` if the predecessor committed everything before quiescing. The successor pops this stash after entering the worktree. |
| `branch` | string | yes | Current branch checked out in the worktree (e.g. `worktree-agent-<issue>`). The successor asserts it matches before resuming. |

**Reviewer `state` variant (required when `role == "reviewer"`):**

- Empty object `{}`. The reviewer is stateless on the filesystem — it writes nothing, owns no worktree, and stashes nothing — so the successor needs no resume blob beyond `current_task_id`. Additional reviewer state fields may be introduced in later versions; none are defined for v1.

**Direction:** teammate → lead (unicast to `team-lead`). Exactly one `handoff_ready` is sent per `request_handoff` received.

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

Optionally, run `swarmkit:clean-remote-worktrees` afterwards to sweep orphaned remote `worktree-agent-*` branches left behind by merged PRs. This is not automatic — invoke it when you want to tidy up.

### Out of scope

- Closing or merging PRs — left open for human review
- Deleting remote branches — only local worktrees and local branches are cleaned by this skill's teardown; `swarmkit:clean-remote-worktrees` handles remote sweep on demand

---

## Constraints

- This skill is experimental and subject to breaking changes as the Agent Teams API evolves
- Never fall through to `swarmkit:swarm` — if the preflight fails, abort
- Never merge into `main` directly — all PRs target the base branch (`develop` by default)
- Commit messages must follow `conventional-commit-message` sub-skill format
- Never mention Claude or add co-author lines in commit messages
- Every PR must reference the issue it closes (`Closes #N`)
