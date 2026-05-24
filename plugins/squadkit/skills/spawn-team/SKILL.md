---
name: spawn-team
description: Spawn a squadkit crew from a profile. Resolves a phonetic team name, optionally cuts an epic feature branch, provisions per-builder worktrees, registers the team via TeamCreate (orchestrator-is-lead), and waits for idle-notification readiness from every spawned member before declaring the team ready. Idempotent against ~/.claude/teams/<name>/config.json.
triggers:
  - "/squadkit:spawn-team"
  - "spawn a squad"
  - "spawn a crew"
  - "stand up a team"
  - "bootstrap a squad"
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Agent, SendMessage, TeamCreate, TeamDelete, Skill
---

# Squadkit Spawn Team

Materialize a crew of agents from a profile. The skill picks an unused phonetic name, loads the crew roster, optionally creates an epic feature branch, provisions per-builder worktrees, registers the team via `TeamCreate`, spawns each non-lead member, and confirms readiness via the harness's idle-notification signal before the orchestrator (which IS the team-lead) enters its dispatch loop.

**Orchestrator-is-lead model.** The session running this skill IS the team-lead. The skill never spawns a separate `squadkit:team-lead` agent and never reserves a `team-lead` slot via `TeamCreate({agent_type: ...})` — both produce phantom roster entries that break sender attribution and routing. Step 8 spawns only the non-lead members from the resolved roster.

## Input

`$ARGUMENTS` — flag string. All flags are optional. The skill prompts via `AskUserQuestion` only when a required interaction is missing (e.g. epic confirmation).

| Flag | Default | Effect |
|------|---------|--------|
| `--profile <name>` | `all-rounder` | Crew profile to load from `plugins/squadkit/crews/<name>.yaml`. |
| `--builders <N>` | `2` | Override the builder count from the profile. Capped at 5. |
| `--with <role>` | none | Add a role to the resolved roster (count=1). Repeatable. |
| `--without <role>` | none | Remove every member with the given role from the roster. Repeatable. |
| `--name <custom>` | auto | Override the team name. Skips phonetic auto-naming. |
| `--epic <slug>` | none | Cut `feature/<slug>-<issue>` from the configured base branch and pin `claude.flowkit.prBase`. If omitted, prompt. **Rejected when the resolved profile has `kind: discovery`.** |
| `--issues <range>` | none | Issue numbers / ranges to load as the team's initial backlog. Accepts the swarmkit grammar: `1319,1329,1331` or `1319-1337` (inclusive). Resolved (open, non-on-hold) list is forwarded to the lead's first dispatch prompt as a structured backlog table. |
| `--brief <text\|@path>` | none | Mission brief embedded into the architect's spawn prompt under `## Mission brief`. Accepts inline text (`--brief "the brief"`) or a file reference (`--brief @./path/to/brief.md`). **Required when the resolved profile has `kind: discovery`** (prompt via `AskUserQuestion` if missing). Optional and otherwise ignored when `kind: execution`. |
| `--mode <inherit\|auto\|bypass\|none>` | `inherit` | Permission mode for spawned members. `inherit` (the default) triggers an interactive `AskUserQuestion` prompt at step 2.5 that lets the user pick `auto`, `bypass`, or `none` — there is no programmatic detection of the parent session's runtime mode. `auto`: skip the prompt, pass `mode: "auto"` to every spawn, AND force `model: "opus"` on every member regardless of role frontmatter (the all-members-opus rule — see step 8). **`auto` mode requires an Anthropic-plan tier (Pro / Max / Team / Enterprise) and is not available on Bedrock, Vertex, or other third-party providers — pick `bypass` or `none` if you're on those.** `bypass`: skip the prompt, pass `mode: "bypassPermissions"` to every spawn; models stay role-default; available everywhere. `none`: skip the prompt, pass no `mode` override (harness defaults apply, members will prompt on tool calls); the explicit "no override, no prompt" escape hatch. Non-interactive callers (slash commands chaining spawn-team, scheduled routines, agents driving spawn-team) MUST pass an explicit `--mode` flag — the prompt only fires for `--mode inherit`. |

### Narrative-tail parsing

If `$ARGUMENTS` carries a trailing narrative such as `to tackle issues 1319-1337` or `for #1319, #1329, #1331`, parse the trailing range/list and treat it as `--issues <range>`. The accepted shapes:

- `to tackle issues <range>` / `tackle issues <range>`
- `for issues <range>` / `for #N, #M, ...`
- `on issues <range>`

If parsing fails (ambiguous tail, mixed flags and narrative), do **not** error — prompt via `AskUserQuestion`:

> Could not parse a `--issues` range from the trailing narrative. Continue without an issue scope, or supply one now?

Options: `Skip — no scope`, `Provide range`, `Cancel`.

## Process

### 1. Resolve the repo root and base branch

Squadkit always reads/writes config relative to the **main repo root**, never a worktree:

```bash
COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "ERROR: not inside a git repository" >&2; exit 1; }
case "$COMMON" in
  /*) ;;
  *)  COMMON="$PWD/$COMMON" ;;
esac
REPO_ROOT=$(cd "$(dirname "$COMMON")" && pwd)
REPO_NAME=$(basename "$REPO_ROOT")
SQUAD_CONFIG="$REPO_ROOT/.squadkit/config.json"
```

Read the base branch defensively from `.squadkit/config.json`. If the file or key is missing, fall back to `develop`:

```bash
BASE_BRANCH=$(jq -r '.baseBranch // "develop"' "$SQUAD_CONFIG" 2>/dev/null || echo "develop")
```

Never hardcode `develop` elsewhere in the runbook — every reference uses `${BASE_BRANCH}` resolved here.

### 2. Parse arguments

Extract every flag from `$ARGUMENTS`. Treat unknown flags as an error and stop, but always run the **narrative-tail parser** described in the Input section before declaring an unknown-flag error — a trailing `to tackle issues 1319-1337` is valid input, not garbage.

- Collect `--with` and `--without` into lists (each may appear multiple times).
- Coerce `--builders` to an integer; reject non-numeric input. If the value exceeds 5, cap it at 5 and warn.
- For `--issues <range>`: resolve via the swarmkit `gh-fetch-issues` sub-skill (see step 5.5) — do not implement filtering inline.
- For `--brief <value>`: capture the raw value verbatim. Do **not** read the file or apply discovery/execution gating yet — that happens in step 5.6 once the crew profile (and its `kind:`) is loaded.

### 2.5 Resolve the effective permission mode

The skill cannot programmatically detect the parent orchestrator's permission mode — the harness exposes no runtime signal for it. Path C resolves the mode interactively instead.

Resolve `RESOLVED_MODE`:

- If `--mode auto`, `--mode bypass`, or `--mode none` was passed explicitly, use it verbatim and skip the prompt. Set `MODE_SOURCE=explicit flag`.
- If `--mode inherit` (the default — i.e. `--mode` was not passed, or was passed as `inherit`), call `AskUserQuestion` with the following three options. Set `MODE_SOURCE=user-selected via prompt` and `RESOLVED_MODE` to the user's selection.

  > Question: `Permission mode for spawned members?`
  >
  > Options:
  >
  > - **auto** — "Fire-and-forget. All members forced to opus. Requires Anthropic-plan tier (Pro / Max / Team / Enterprise) — not available on Bedrock, Vertex, or other third-party providers. Choose bypass or none instead if you're on those."
  > - **bypass** — "Propagate `bypassPermissions` to every member. Models stay role-default. Available everywhere."
  > - **none** — "No `mode` override. Harness defaults apply (members will prompt on tool calls). Available everywhere."

After resolution, print one line:

```
permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)
```

`RESOLVED_MODE` and `MODE_SOURCE` are persisted into the team config in step 10 and surfaced again in the dispatch summary in step 11.

**Non-interactive callers.** `AskUserQuestion` blocks for human input. Callers that need non-interactive invocation (slash commands chaining `/squadkit:spawn-team`, scheduled routines, agents driving spawn-team programmatically) MUST pass an explicit `--mode` flag — the prompt only fires for `--mode inherit`. Use `--mode none` when the intent is "no override, no prompt."

### 3. Resolve the team name

If `--name <custom>` is provided, use it verbatim (after sanitizing to `[a-z0-9-]+`). Otherwise derive `<repo>-<phonetic>`:

```bash
PHONETIC=(alpha bravo charlie delta echo foxtrot golf hotel india juliet
          kilo lima mike november oscar papa quebec romeo sierra tango
          uniform victor whiskey xray yankee zulu)

for letter in "${PHONETIC[@]}"; do
  CANDIDATE="${REPO_NAME}-${letter}"
  if [ ! -e "$HOME/.claude/teams/${CANDIDATE}/config.json" ]; then
    TEAM_NAME="$CANDIDATE"
    break
  fi
done
```

If every phonetic letter is taken, stop and report: ask the user to recycle a stale team or pass `--name` explicitly. Do not invent a 27th letter.

#### 3.1 UUID-orphan pre-flight sweep

The harness occasionally creates UUID-named team dirs (e.g. `2c2c01f2-00d4-41f7-8892-adb4fc667428`) — typically orphans from interrupted spawn sessions. They do not collide with phonetic resolution but they accumulate under `~/.claude/teams/` and have no live members.

List them:

```bash
find "$HOME/.claude/teams" -mindepth 1 -maxdepth 1 -type d \
  -regex '.*/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}$'
```

For each candidate, confirm it has **no live members** (every entry in `members[]` has empty/null `tmuxPaneId` or no recent activity). If at least one orphan is detectable, prompt the user via `AskUserQuestion`:

> Found N UUID-named team dir(s) under `~/.claude/teams/` with no live members. Clean them via `TeamDelete`?

Options: `Clean all`, `Skip`, `Pick which to clean` (multi-select via a follow-up question).

For each chosen orphan, call `TeamDelete({team_name: <uuid>})`. Never delete a UUID dir that still has a live member — surface a warning instead.

### 4. Idempotency check

If `~/.claude/teams/${TEAM_NAME}/config.json` already exists, **do not respawn members**. Read the file, list each existing member's role, session UUID, and worktree path, and report which (if any) are still alive. Ask the user via `AskUserQuestion` whether to:

- `Reuse` — print the existing roster and exit (no new agents).
- `Add missing` — only spawn members named in the resolved roster that aren't already in the config.
- `Cancel` — abort.

Re-running the skill against an existing config must never duplicate a live member.

### 5. Load the crew profile

Read `plugins/squadkit/crews/<profile>.yaml`. Validate the schema:

```yaml
name: <string>
description: <string>
kind: <string, optional, default "execution">    # one of: execution | discovery
members:
  - role: <string>
    count: <int, optional, default 1>
```

If the file is missing or fails validation, stop with a diagnostic. If `kind:` is present but not one of `execution` or `discovery`, reject the profile with:

> Crew profile `<profile>` declares `kind: <value>`, which is not a recognized crew kind. Allowed values: `execution`, `discovery`.

If `kind:` is omitted, default to `execution` — this preserves backward compatibility with crew profiles authored before the field existed (`all-rounder`, `design`, `qa`, `builder`).

**Crew kinds.**

- `execution` (default) — produces code. Provisions per-builder worktrees, supports `--epic` and `claude.flowkit.prBase` pinning, ships PRs.
- `discovery` — read-only investigative crew (architect + explorer + designer style). Produces blueprints / GitHub issue comments, not code. Skips worktree provisioning, rejects `--epic`, skips `claude.flowkit.prBase` pinning. Requires `--brief`.

Build the resolved roster:

1. Expand each `members[*]` entry into `count` instances of `{role}`.
2. If `--builders <N>` was given, override every `builder` instance count to N (capped at 5).
3. Apply `--with <role>` by appending one instance per occurrence.
4. Apply `--without <role>` by removing every instance with that role.
5. **Strip every `team-lead` instance from the resolved roster** — the orchestrator IS the lead. The roster passed to step 8 contains only non-lead members. If a profile lists `team-lead` (legacy), drop it silently; do not re-add it.

### 5.5 Resolve the issue scope (optional)

If `--issues <range>` was provided (or parsed from the narrative tail), invoke the swarmkit `gh-fetch-issues` sub-skill to expand the range and apply the canonical filters (open + non-on-hold + non-`status:in-progress`):

```
Skill({skill: "swarmkit:gh-fetch-issues", args: "<resolved range>"})
```

The sub-skill returns a list of `{number, title, labels, body-excerpt}` records. Persist this list as `RESOLVED_BACKLOG` for forwarding into the lead's first dispatch prompt (step 11).

If the range expands to zero issues after filtering, warn the user and ask via `AskUserQuestion` whether to proceed with no preset backlog or abort. Do not silently spawn a team with an empty work-scope when one was explicitly requested.

If `--issues` was not provided, skip this step — `RESOLVED_BACKLOG` stays empty and the lead is dispatched without a preset backlog (it works against the team's own task list).

### 5.6 Resolve the mission brief and gate by `kind:`

This step runs after the crew profile (with its resolved `kind:`) is loaded.

**Discovery-mode `--epic` rejection.** If the resolved profile has `kind: discovery` and `--epic` was provided (either as a flag or via the prompt), stop with:

> Crew profile `<profile>` is `kind: discovery` and produces issue comments rather than code. The `--epic` flag is incompatible with discovery crews — drop it and re-run.

**Brief resolution.** If `--brief <value>` was provided, resolve it to text now:

- If `<value>` starts with `@`, treat the rest as a path. Read the file (relative to the repo root if not absolute). If the file is missing or unreadable, stop with: `--brief @<path> could not be read: <error>`.
- Otherwise treat `<value>` verbatim as the brief text.
- Trim trailing whitespace. If the resulting text is empty, stop with: `--brief value resolved to empty content. Provide a non-empty brief.`

Persist the resolved string as `MISSION_BRIEF`.

**Discovery requires a brief.** If `kind: discovery` and `MISSION_BRIEF` is empty (no `--brief` provided), prompt via `AskUserQuestion`:

> Crew profile `<profile>` is `kind: discovery`, which requires a `--brief`. Provide one now, or cancel?

Options: `Provide brief — paste inline`, `Provide brief — supply @path`, `Cancel`.

If the user cancels, abort the spawn. Otherwise re-run brief resolution against the supplied value.

**Execution + brief.** When `kind: execution` and `--brief` is provided, `MISSION_BRIEF` is still embedded into the architect's spawn prompt under `## Mission brief` — but the absence of `--brief` is not an error.

**Epic context prepending (execution only).** This composition only applies to `kind: execution` crews — `--epic` is rejected for discovery crews (see the rejection guard at the top of this step). If `--epic <slug>` was provided alongside `--brief`, fetch the GitHub issue body for `<issue>` (the issue number passed with `--epic`) via `gh issue view <issue> --json body --jq .body` and prepend it to `MISSION_BRIEF` as:

```
## Epic context

<epic body>

## Mission brief

<resolved brief text>
```

If the epic fetch fails (network, missing issue, auth), warn but do not abort — fall back to the brief alone, and surface the failure in the final summary.

If `--brief` was not provided, leave `MISSION_BRIEF` empty.

### 6. Epic feature-branch ownership

**Skip entirely when `kind: discovery`.** Discovery crews never cut a feature branch and never pin `claude.flowkit.prBase` — they produce issue comments, not PRs. Set `WORK_BRANCH=${BASE_BRANCH}` and proceed to step 6.5 without prompting for an epic.

**Pre-flight rule (execution only).** Any spawn that will produce three or more child PRs MUST run on a feature branch — not directly on `${BASE_BRANCH}`. When the resolved roster includes more than one builder, or the user's intent names three or more deliverables, default the prompt toward cutting an epic and only accept `Use ${BASE_BRANCH}` after the user confirms the work is genuinely a single PR's worth.

**(execution only — skip this block when kind: discovery)**

If `--epic <slug>` was provided, the skill cuts the epic branch. Otherwise prompt via `AskUserQuestion`:

- **Question**: `No --epic given. Cut a feature branch for this team, or run on ${BASE_BRANCH} directly?`
- **Options**:
  - `Cut epic` — ask for slug + issue number, then proceed with the epic flow.
  - `Use ${BASE_BRANCH}` — skip the epic flow, members work directly on the base branch.
  - `Cancel` — abort.

When cutting an epic:

1. Resolve `<issue>` from `--epic` arguments or prompt for it. The expected slug is kebab-case (`[a-z0-9-]+`).
2. **Cross-pin guard.** Before invoking cut-epic, read the existing pin:

   ```bash
   EXISTING_PIN=$(git config --local --get claude.flowkit.prBase 2>/dev/null || true)
   if [[ -n "$EXISTING_PIN" && "$EXISTING_PIN" =~ ^feature/ && "$EXISTING_PIN" != "feature/${slug}-${issue}" ]]; then
     echo "spawn-team: an epic is already pinned (\`$EXISTING_PIN\`)." >&2
     echo "  Re-run without --epic and answer \`Use \${BASE_BRANCH}\` to spawn against the base branch instead," >&2
     echo "  or re-run with --epic matching the pinned slug to reuse it." >&2
     exit 1
   fi
   ```

   When the existing pin matches the resolved feature branch, proceed silently — cut-epic is idempotent and will reuse the branch.

3. Invoke `flowkit:cut-epic` via the Skill tool, forwarding the resolved slug and issue number verbatim (cut-epic input shape 2 — issue + slug pair):

   ```
   Skill({skill: "flowkit:cut-epic", arguments: "<slug> <issue>"})
   ```

   cut-epic owns the rest: idempotent branch create-or-reuse from `origin/${BASE_BRANCH}`, push to origin, and pin `claude.flowkit.prBase` to `feature/<slug>-<issue>`. Surface cut-epic's report in spawn-team's final summary.

4. Set `WORK_BRANCH=feature/<slug>-<issue>`. The pin is now live; every member's `flowkit:open-pr` invocation in this session targets the epic branch automatically.

`WORK_BRANCH=${FEATURE_BRANCH}` from here on; if no epic was cut, `WORK_BRANCH=${BASE_BRANCH}`.

### 6.5 Stale-worktree pre-flight

Before provisioning new worktrees, sweep the repo's `.claude/worktrees/` for stale paths that don't match the resolved roster.

```bash
existing=$(find .claude/worktrees -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null || true)
```

If any `existing` entry is **not** a member id in the resolved roster (e.g. `builder-1` survives but `tester` is no longer in scope, or the dir is from a completely different epic like `feat/library-cleanup-1298a`), invoke `swarmkit:clean-worktrees` as a sub-skill:

```
Skill({skill: "swarmkit:clean-worktrees"})
```

This removes orphan worktrees and their orphaned `worktree-agent-*` branches. It is safe to run when nothing is stale (it reports "nothing to clean" and exits).

If the user has explicitly opted to keep specific stale paths, surface them via `AskUserQuestion` before invoking the sub-skill.

### 7. Worktree provisioning

**Skip entirely when `kind: discovery`.** Discovery crews are read-only and produce no per-builder branches; every member shares the main workspace. Skip this step (and the env-file seeding subsection below) and proceed to step 7.5.

Count builders in the resolved roster.

- **Singleton (1 builder)**: every member shares the current workspace. Skip worktree creation. Skip the env-file seeding subsection — there's no destination worktree to seed.
- **Multi-builder (>1 builder)**: create one worktree per builder under `.claude/worktrees/<member>/`:

```bash
mkdir -p .claude/worktrees
for member in "${MULTI_WORKTREE_MEMBERS[@]}"; do
  WT_PATH=".claude/worktrees/${member}"

  if [ -d "${WT_PATH}" ]; then
    actual_branch=$(git -C "${WT_PATH}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "<unreadable>")
    expected_branch="${WORK_BRANCH}"
    if [ "${actual_branch}" != "${expected_branch}" ] && [ "${actual_branch}" != "HEAD" ]; then
      # Stale worktree — ask user before reusing
      # AskUserQuestion: "Worktree ${WT_PATH} exists on '${actual_branch}', expected '${expected_branch}' (or detached at the epic HEAD). Sweep, reuse, or abort?"
      # Options:
      #   Sweep  — git worktree remove --force "${WT_PATH}" && git branch -D "${actual_branch}" 2>/dev/null; recreate below
      #   Reuse  — continue (caller accepts the inherited branch)
      #   Abort  — exit the skill
      :
    else
      continue
    fi
  fi

  git worktree add --detach "${WT_PATH}" "${WORK_BRANCH}"
done
```

`<member>` is the per-instance member id (e.g. `builder-1`, `builder-2`). Non-builder members in a multi-builder config also share the workspace — only the builders fan out — unless the profile or future flags say otherwise.

**Why `--detach`.** Step 6 already checks the main worktree out onto `${WORK_BRANCH}`. A bare `git worktree add <path> <work_branch>` would refuse with `'feature/<slug>-<N>' is already used by worktree at '<main>'` because git holds branch refs to a single worktree at a time. Detached HEAD lets each builder start at the epic HEAD without contention; builders create per-issue branches (e.g. `worktree-agent-<issue>`) off the detached commit when they pick up a task.

**Never silently reuse a stale worktree.** The `if [ -d "${WT_PATH}" ]` short-circuit must always check the worktree's current branch against `${WORK_BRANCH}` (or detached) and prompt the user before reusing — inheriting a half-merged feature branch from a previous team is a discipline failure.

`Agent({isolation: "worktree"})` is unreliable for multi-builder spawning today, so the skill always uses manual `git worktree add` and passes the resolved path into each spawned agent.

#### Worktree seeding (env files and other ignored files)

Repo-local credential files (`.env.local`, `.env.test.local`, etc.) are gitignored and therefore do not appear in a fresh worktree. Builders that pick up a task immediately fail their `${verify.test}` step until they manually copy them.

After provisioning each per-builder worktree, seed it with the project's ignored env files. Two modes:

1. **Auto-detect** (default) — detect ignored env files in the main worktree and copy them in:

   ```bash
   cd "$REPO_ROOT"
   git ls-files --others --ignored --exclude-standard \
     | grep -E '^(\.env(\.local|\.[a-z-]+\.local)?|\.env-[a-z-]+)$' \
     | while read -r envfile; do
         cp "$REPO_ROOT/$envfile" "$WT_PATH/$envfile"
       done
   ```

2. **Explicit override** — if `.squadkit/config.json` defines a `worktreeSeed: [...]` list, copy exactly that list (relative to the repo root) and skip the auto-detection. This handles projects that need non-env files seeded too (certificates, config snippets, etc.):

   ```json
   {
     "worktreeSeed": [".env.local", ".env.test.local", "config/secrets.json"]
   }
   ```

If a listed file is missing, warn but do not error — surface every missing path in the final summary so the user can remediate.

**Skip for singleton-builder profiles.** They share the main workspace; nothing to copy.

### 7.5 Register the team via TeamCreate

Before spawning members, register the team with the harness:

```
TeamCreate({team_name: "${TEAM_NAME}", description: "<one-line description from the crew profile>"})
```

**Do NOT pass `agent_type`.** Passing `agent_type: "team-lead"` (or any role) reserves a placeholder slot under that name, with no live process behind it. When the actual member spawns later, the harness renames it to `<role>-2` because the slot is taken. The result is a phantom roster entry that confuses routing and observability.

The orchestrator IS the lead — it does not need a slot. Members address their messages to peers (`builder-1`, `tester`, etc.) and to the orchestrator implicitly via the harness's parent-session inbox.

#### Phantom-slot sanity check

Immediately after `TeamCreate`, list the team's members. If any member has `agentId: "<role>@<team>"` with empty `tmuxPaneId`, that's a phantom slot from a stray `agent_type` and must be flagged:

```bash
jq '.members[] | select(.tmuxPaneId == null or .tmuxPaneId == "") | .agentId' \
  "$HOME/.claude/teams/${TEAM_NAME}/config.json"
```

If output is non-empty, halt the skill and surface the phantom — never proceed with a polluted roster.

### 8. Spawn non-lead members

For each resolved member (the orchestrator is the lead — never spawn one here), spawn a background `Agent` with the role contract loaded from `plugins/squadkit/agents/<role>.md`. If a project-local overlay exists at `.claude/agents/<role>.md`, **append** it to the contract (project-local layered on top of the plugin contract — project-local wins on conflict).

Each spawned agent receives:

- `member_id` (e.g. `builder-1`, `reviewer`)
- `role`
- `team_name`
- `worktree_path` (absolute; equals `REPO_ROOT` for shared-workspace members)
- `work_branch` (`${WORK_BRANCH}`)
- `base_branch` (`${BASE_BRANCH}`)
- `squadkit_config_path` (`${SQUAD_CONFIG}`)

**Architect-only mission brief.** When spawning the `architect` member and `MISSION_BRIEF` is non-empty, append the brief verbatim to the architect's spawn prompt as a trailing section:

```markdown
## Mission brief

<MISSION_BRIEF, verbatim — including any prepended `## Epic context` from step 5.6>
```

The brief is included verbatim — do not paraphrase, summarize, or re-order its contents. If `--epic` was provided alongside `--brief`, step 5.6 has already prepended the `## Epic context` block; the architect sees both sections in a single embedded payload.

**Other roles stay mission-agnostic.** Do **not** embed `MISSION_BRIEF` in the spawn prompts for explorer, designer, builder, reviewer, tester, or any other non-architect role. They receive the brief (if at all) only when the team-lead routes a scoped task to them — never via spawn-time injection.

#### Spawn-time mode + model selection

`RESOLVED_MODE` (resolved in step 2.5) controls the permission `mode` passed to each `Agent({mode})` spawn and, when `auto`, forces opus on every member:

| `RESOLVED_MODE` | `Agent({mode})` per spawn | Model override |
|-----------------|---------------------------|----------------|
| `auto` | `"auto"` | **all members forced to `opus`** — architect, builder, reviewer, tester, explorer, designer — regardless of role frontmatter |
| `bypass` | `"bypassPermissions"` | none — role frontmatter default |
| `none` | not passed — harness defaults apply | none — role frontmatter default |

**Rationale.** When auto mode is active, sonnet-tier crew members prompt for permission approval on every tool call, defeating the autonomous-flow benefit of auto. Opus-tier members run cleanly under the same condition (see Harness constraints). The simpler invariant — `auto ⇒ opus everywhere` — is easier to reason about than the previous "non-builders only" carve-out, and any sonnet member under auto mode breaks autonomous flow regardless of role. The cost trade-off (builders burn budget faster on opus during long-running implementation work) is accepted in exchange for the simpler invariant; if budget is a concern, pick `bypass` or `none` instead.

When `RESOLVED_MODE=auto` and a role's frontmatter declared sonnet, log per spawn:

```
RESOLVED_MODE=auto → forcing opus on <role>
```

**Auto-mode availability.** `auto` mode is an Anthropic-plan-tier feature (Pro / Max / Team / Enterprise) and is **not available on Bedrock, Vertex, or other third-party providers**. The step 2.5 prompt and the `--mode` flag table both surface this caveat — operators on those providers should pick `bypass` or `none` instead.

Capture the session UUID returned by each `Agent` spawn — it lands in the harness-managed config automatically; the squadkit-specific sibling file (step 10) only stores the squadkit metadata, not the per-member roster.

### 8.5 Tool-registry validation probe

After spawning the non-lead members but **before** waiting on idle notifications (step 9), probe the lead's coordination tools end-to-end. The orchestrator IS the lead, so "the lead" here means the session running this skill — probe your own tool registry.

The probe is a `SendMessage` no-op: send a sentinel message to a known-addressable target (the first spawned member, or any teammate the harness exposes by name) with a uniquely identifiable payload, then assert two things:

1. The `SendMessage` call returns a success status — not a tool-error, not a missing-tool error.
2. The harness-emitted `summary` payload for that call matches the probe content (the digest of what was sent equals the digest of what the harness reports as delivered).

**Probe content shape:**

```
TO: <first-spawned-member-id>
Subject: spawn-probe-<TEAM_NAME>-<short-uuid>
Body: "Spawn probe for ${TEAM_NAME}. No action required — discard on receipt."
```

The probe is a no-op for the receiving member: it carries no task, no brief, no ack request. Members should treat unknown `Subject: spawn-probe-*` messages as discardable.

**On success:** record the probe result (timestamp + delivered digest) in the spawn summary, then proceed to step 9.

**On failure (tool error, schema mismatch, or missing tool):** halt squad creation immediately. Do not proceed to step 9. Surface to the user:

- Which tool was gated (e.g. `SendMessage`, `TaskCreate`, `Agent`).
- The exact error text returned by the harness.
- A recommendation: re-provision the orchestrator with the missing tool granted, or respawn the team in a session that has the full registry.

This catches the failure mode where the lead silently spins up missing one of the tools its role contract requires (`SendMessage`, `TaskCreate`, `TaskList`, `TaskGet`, `Agent`) — turning a multi-turn diagnostic loop into a single clear failure at spawn time.

**Cross-reference.** The orchestrator playbook entry `lead-cannot-dispatch` in `plugins/squadkit/agents/team-lead.md` handles the runtime variant of this same problem (the lead reports an identical tool error twice). The probe is the spawn-time prevention; the playbook entry is the runtime fallback.

### 9. Readiness confirmation — idle-notification-as-ack

The earlier ping/ack protocol could not be implemented as written: the orchestrator has no addressable name in the team, so members cannot ack it by name. Instead, rely on the harness's automatic idle notification.

Each spawned background `Agent` emits an idle notification to the parent session when its first turn ends. That notification proves the agent is alive and reachable. Use it as the readiness ack — no explicit ping/ack round-trip is required.

After all non-lead members are spawned (count = N):

1. Wait for **N idle notifications**, one per spawned member, with a per-member timeout of **60 seconds**.
2. As each notification arrives, mark that member ready.
3. If any member fails to idle within 60s, surface the missing role and ask the user via `AskUserQuestion`:

   > Member `<role>` did not idle within 60s. Retry, drop, or abort?

   Options: `Retry — wait another 60s`, `Drop — proceed without this member`, `Abort — stop the spawn`.

Because the orchestrator IS the lead, the original "lead spawned in parallel may miss member acks" problem does not apply — the orchestrator is always present to receive idle notifications as they arrive.

If a future variant of this skill ever spawns a separate lead agent (legacy path), instruct that lead in its first prompt to read `~/.claude/teams/<team>/config.json` and confirm the roster from the harness-managed `members[]` array, rather than relying on inbound idle notifications it may have already missed.

### 10. Persist squadkit metadata (sibling file, not the harness config)

`TeamCreate` (step 7.5) and each `Agent` spawn (step 8) populate `~/.claude/teams/${TEAM_NAME}/config.json` automatically — that file is **harness-managed**. The harness adds entries on every Agent spawn, recording `agentId`, `name`, `agentType`, `model`, `cwd`, `tmuxPaneId`, `joinedAt`, `color`, etc. **Do not overwrite it** — overwriting clobbers the members[] array and breaks peer addressability.

Squadkit-specific metadata (work branch, base branch, epic slug, repo root) lives in a sibling file:

```
~/.claude/teams/${TEAM_NAME}/squadkit.json
```

Schema:

```json
{
  "work_branch": "<branch>",
  "base_branch": "<branch>",
  "epic": "<slug or null>",
  "repo_root": "<absolute-path>",
  "profile": "<profile-name>",
  "kind": "<execution|discovery>",
  "brief_provided": <true|false>,
  "permissionMode": "<auto|bypassPermissions|none>",
  "spawned_at": "<ISO-8601 timestamp>"
}
```

`brief_provided` records whether `--brief` was supplied at spawn time; the brief content itself is not persisted (it lives only in the architect's spawn prompt).

`permissionMode` records `RESOLVED_MODE` from step 2.5 so mid-session `Agent` spawns (between-wave swaps, preemptive handoff successors) can read it back and propagate the same authority. Map `RESOLVED_MODE` to the persisted value as follows: `auto` → `"auto"`, `bypass` → `"bypassPermissions"`, `none` → `"none"`. The team-lead role contract (`plugins/squadkit/agents/team-lead.md`) reads this field before every successor/swap spawn — without it, inheritance silently degrades after the first wave.

Wait until every member has emitted its idle notification in step 9 before writing this file; partial-roster sibling files corrupt downstream reads. `mkdir -p` the parent directory before writing. The harness's `config.json` is the source of truth for the roster; `squadkit.json` is the source of truth for squadkit-only coordination state. Never duplicate `members[]` here.

Sibling files are squadkit-local state — never check them in.

### 11. Hand off to the team-lead (the orchestrator itself)

The orchestrator IS the lead — there is no separate handoff message to send. Instead, print a summary including:

- Team name and profile.
- Work branch (and whether it was cut as an epic).
- Roster: member id → role → worktree path.
- Path to the harness-managed `config.json` and the sibling `squadkit.json`.
- The fact that `claude.flowkit.prBase` is pinned (if applicable) and how to clear it (`git config --unset claude.flowkit.prBase`).
- Any worktree-seeding warnings (missing files listed in `worktreeSeed`).
- `permission mode: <RESOLVED_MODE> (<MODE_SOURCE>)` — the same line printed at step 2.5, repeated here so the human has a record in the final summary.

Then begin the dispatch loop per the team-lead role contract (`plugins/squadkit/agents/team-lead.md`). The first dispatch prompt sent to each builder MUST include the resolved backlog (if `RESOLVED_BACKLOG` is non-empty) as a structured section:

```markdown
## Backlog (resolved from --issues)

| # | Title | Labels |
|---|-------|--------|
| 1319 | <title> | bug, priority:high |
| 1329 | <title> | enhancement |
| ...
```

If `RESOLVED_BACKLOG` is empty, dispatch the lead's loop with no preset scope — it works against the team's own task list.

## Orchestrator playbook

These branches mirror the named entries in `plugins/squadkit/agents/team-lead.md` — the spawn skill carries them too because spawn time is when the orchestrator first activates these protocols.

### `lead-cannot-dispatch`

If after handing off to the dispatch loop the lead reports the same tool error twice with identical text on consecutive turns, **escalate to re-provision — do not retry a third time**. Identical-text repetition signals tool-gating, not a transient failure. Surface the gated tool to the user, recommend a clean respawn, and halt the dispatch loop. The step 8.5 probe is designed to catch this at spawn time; this branch is the runtime fallback when something gates a tool mid-session.

### Delivery-receipt channel

The lead writes a delivery receipt per dispatch attempt to `.squadkit/dispatch-log.jsonl` (one JSON object per line) so the orchestrator can distinguish "idle after a successful dispatch" from "idle after a tool-error turn that swallowed the dispatch." The schema:

| Field | Type | Notes |
|-------|------|-------|
| `timestamp` | string (ISO-8601) | When the dispatch attempt was made. |
| `member` | string | Target member id. |
| `task` | string \| number | Task id or issue number being dispatched. |
| `digest` | string | Short content digest of the brief (first 12 chars of a sha256 over the body). |
| `outcome` | string | `sent`, `tool_error`, or `skipped_dedup`. |

Idle ≠ delivery. The orchestrator reads the latest `(member, task)` line before assuming a dispatch landed; on `tool_error`, fall through to the `lead-cannot-dispatch` branch above. The full prose for both branches lives in `plugins/squadkit/agents/team-lead.md` under "Orchestrator playbook" — this section is a deliberate mirror so the spawn skill remains self-contained.

## Harness constraints

These are observed limitations of the `Agent` and `TeamCreate` primitives at the time of writing. The skill works around each one explicitly — do not "fix" the workarounds without first confirming the underlying constraint has been lifted.

- **`TeamCreate({agent_type: ...})` reserves a phantom slot.** Always call `TeamCreate({team_name, description})` without `agent_type`; let actual `Agent` spawns populate the roster.
- **The orchestrator has no addressable name in the team.** Members cannot `SendMessage` to the orchestrator by name. The harness auto-delivers replies to the parent session's next turn; rely on that flow rather than explicit ping/ack.
- **`Agent({isolation: "worktree"})` is unreliable when combined with `team_name`.** The auto-isolation does not fire reliably for team-scoped spawns, so the skill always provisions worktrees manually via `git worktree add --detach` (see step 7) and passes the resolved absolute path into each spawned agent.
- **`git worktree add <path> <branch>` refuses when the main worktree is already on `<branch>`.** Always use `--detach` for per-builder worktrees so the branch ref stays free.
- **`Agent({model})` rejects 1M-context aliases like `opus[1m]`.** The harness validates the model param against a fixed allowlist of bare names. To put a long-running role (tester, reviewer, architect) on the 1M tier, spawn with the bare alias (e.g. `opus`) and rely on the team-lead's between-wave swap protocol to rotate in a fresh successor before context fills.
- **Sonnet-tier crew members prompt for permissions in auto mode.** When auto mode is active and a spawned member is on sonnet, every tool call that would normally proceed silently under auto instead prompts for approval — even though the orchestrator session itself runs autonomously. Opus-tier members do not exhibit this. `RESOLVED_MODE=auto` (see step 8) forces opus on every member — architect, builder, reviewer, tester, explorer, designer — to work around this; without auto mode, role frontmatter defaults apply unchanged.
- **Frontmatter `model:` in `.claude/agents/*.md` is ignored on spawn.** Only the explicit `Agent({model})` parameter controls which model the spawned agent runs on. The frontmatter field is informational for human readers; do not expect it to override the spawn-time parameter, and do not let users assume editing frontmatter changes a live team.
- **Frontmatter `tools:` is overridden by a default allowlist for some roles.** The harness applies its own tool subset on spawn that may strip tools the role contract declared. Always include `Bash` in the explicit spawn `tools` param so an agent missing `Glob`/`Grep`/`LS` can still fall back to `find`/`grep`/`ls` and complete its work.

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | The canonical epic-cutting primitive. `spawn-team --epic` invokes this skill via the Skill tool so both entry points share one implementation. |
| `flowkit:open-pr` / `flowkit:pr` | Member PRs target `claude.flowkit.prBase` automatically once the spawn pins it. |
| `swarmkit:gh-fetch-issues` | Resolves `--issues <range>` into a filtered (open + non-on-hold) list for the lead's first dispatch prompt. |
| `swarmkit:clean-worktrees` | Pre-flight sweep when stale `.claude/worktrees/*` paths exist that don't match the resolved roster. |
| `swarmkit:swarm` | Independent fan-out for issue queues. Use `swarmkit` when work is already sliced into issues; use `spawn-team` when you want a coordinated long-running crew. |

## Crew shapes

Two coordination shapes are supported:

- **Execution crews** (default) — architect drafts blueprints, builders implement, tester/reviewer gate. Output is merged code via PRs.
- **Discovery crews** (`kind: discovery`) — architect IS the lead and synthesizes explorer/designer replies into long-form blueprints posted as GitHub issue comments. Builders are absent. See [`../../docs/patterns/discovery-coordination.md`](../../docs/patterns/discovery-coordination.md) for the full coordination protocol, role scopes, deliverable shape, stop condition, and a worked example.

## Known issue: TeamDelete leaves zombie subprocesses

`TeamDelete` returns success but does not signal or kill the long-running agent processes whose `--team-name` flag matches. This is a harness-level limitation and will be addressed upstream (see #924). Until the harness fix lands, operators should sweep lingering agent subprocesses manually after calling `TeamDelete` to tear down a team:

```bash
ps aux \
  | grep -- "--team-name <team-name>" \
  | grep -v grep \
  | awk '{print $2}' \
  | xargs -r kill
```

Replace `<team-name>` with the team name passed to `TeamDelete`. Run this sweep immediately after `TeamDelete` returns — the zombie processes consume no dispatch but do hold open file descriptors and tmux panes.
