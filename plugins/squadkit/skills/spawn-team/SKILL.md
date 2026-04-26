---
name: spawn-team
description: Spawn a squadkit crew from a profile. Resolves a phonetic team name, optionally cuts an epic feature branch, provisions per-builder worktrees, and waits for SendMessage acks from every member before declaring the team ready. Idempotent against ~/.claude/teams/<name>/config.json.
triggers:
  - "/squadkit:spawn-team"
  - "spawn a squad"
  - "spawn a crew"
  - "stand up a team"
  - "bootstrap a squad"
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion, Agent, SendMessage
---

# Squadkit Spawn Team

Materialize a crew of agents from a profile. The skill picks an unused phonetic name, loads the crew roster, optionally creates an epic feature branch, provisions per-builder worktrees, spawns each member, and confirms readiness via `SendMessage` ack before handing control to the team-lead.

## Input

`$ARGUMENTS` — flag string. All flags are optional. The skill prompts via `AskUserQuestion` only when a required interaction is missing (e.g. epic confirmation).

| Flag | Default | Effect |
|------|---------|--------|
| `--profile <name>` | `all-rounder` | Crew profile to load from `plugins/squadkit/crews/<name>.yaml`. |
| `--builders <N>` | `2` | Override the builder count from the profile. Capped at 5. |
| `--with <role>` | none | Add a role to the resolved roster (count=1). Repeatable. |
| `--without <role>` | none | Remove every member with the given role from the roster. Repeatable. |
| `--name <custom>` | auto | Override the team name. Skips phonetic auto-naming. |
| `--epic <slug>` | none | Cut `feature/<slug>-<issue>` from the configured base branch and pin `claude.flowkit.prBase`. If omitted, prompt. |

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

Extract every flag from `$ARGUMENTS`. Treat unknown flags as an error and stop.

- Collect `--with` and `--without` into lists (each may appear multiple times).
- Coerce `--builders` to an integer; reject non-numeric input. If the value exceeds 5, cap it at 5 and warn.

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
members:
  - role: <string>
    count: <int, optional, default 1>
```

If the file is missing or fails validation, stop with a diagnostic.

Build the resolved roster:

1. Expand each `members[*]` entry into `count` instances of `{role}`.
2. If `--builders <N>` was given, override every `builder` instance count to N (capped at 5).
3. Apply `--with <role>` by appending one instance per occurrence.
4. Apply `--without <role>` by removing every instance with that role.

The team-lead role is always required — if the profile or overrides remove it, re-add a single instance and warn.

### 6. Epic feature-branch ownership

If `--epic <slug>` was provided, the skill cuts the epic branch. Otherwise prompt via `AskUserQuestion`:

- **Question**: `No --epic given. Cut a feature branch for this team, or run on ${BASE_BRANCH} directly?`
- **Options**:
  - `Cut epic` — ask for slug + issue number, then proceed with the epic flow.
  - `Use ${BASE_BRANCH}` — skip the epic flow, members work directly on the base branch.
  - `Cancel` — abort.

When cutting an epic:

1. Resolve `<issue>` from `--epic` arguments or prompt for it. The expected slug is kebab-case (`[a-z0-9-]+`).
2. Compose `FEATURE_BRANCH="feature/<slug>-<issue>"`.
3. Cut it from the configured base branch — idempotent against existing branches:

```bash
git fetch origin "${BASE_BRANCH}"
if git show-ref --verify --quiet "refs/heads/${FEATURE_BRANCH}"; then
  git checkout "${FEATURE_BRANCH}"
elif git show-ref --verify --quiet "refs/remotes/origin/${FEATURE_BRANCH}"; then
  git checkout -b "${FEATURE_BRANCH}" "origin/${FEATURE_BRANCH}"
else
  git checkout -b "${FEATURE_BRANCH}" "origin/${BASE_BRANCH}"
fi
git push -u origin "${FEATURE_BRANCH}"
```

4. Pin the PR base for the session:

```bash
git config --local claude.flowkit.prBase "${FEATURE_BRANCH}"
```

The pin is local to the repo (not the worktree) so every member inherits it. `WORK_BRANCH=${FEATURE_BRANCH}` from here on; if no epic was cut, `WORK_BRANCH=${BASE_BRANCH}`.

### 7. Worktree provisioning

Count builders in the resolved roster.

- **Singleton (1 builder)**: every member shares the current workspace. Skip worktree creation.
- **Multi-builder (>1 builder)**: create one worktree per builder under `.claude/worktrees/<member>/`:

```bash
mkdir -p .claude/worktrees
for member in "${MULTI_WORKTREE_MEMBERS[@]}"; do
  WT_PATH=".claude/worktrees/${member}"
  if [ -d "${WT_PATH}" ]; then
    continue
  fi
  git worktree add "${WT_PATH}" "${WORK_BRANCH}"
done
```

`<member>` is the per-instance member id (e.g. `builder-1`, `builder-2`). Non-builder members in a multi-builder config also share the workspace — only the builders fan out — unless the profile or future flags say otherwise.

`Agent({isolation: "worktree"})` is unreliable for multi-builder spawning today, so the skill always uses manual `git worktree add` and passes the resolved path into each spawned agent.

### 8. Spawn members

For each resolved member, spawn a background `Agent` with the role contract loaded from `plugins/squadkit/agents/<role>.md`. If a project-local overlay exists at `.claude/agents/<role>.md`, **append** it to the contract (project-local layered on top of the plugin contract — project-local wins on conflict).

Each spawned agent receives:

- `member_id` (e.g. `builder-1`, `reviewer`)
- `role`
- `team_name`
- `worktree_path` (absolute; equals `REPO_ROOT` for shared-workspace members)
- `work_branch` (`${WORK_BRANCH}`)
- `base_branch` (`${BASE_BRANCH}`)
- `squadkit_config_path` (`${SQUAD_CONFIG}`)

Capture the session UUID returned by each `Agent` spawn — it goes into the persisted team config.

### 9. Readiness confirmation

Before declaring the team ready, every spawned member must `SendMessage`-ack. The skill sends each member a `ping` and waits for an `ack` reply. Members that fail to ack within a reasonable window (default 60s) are reported, and the user is asked whether to retry, drop the member, or abort.

Do not write the team config until every member has acked.

### 10. Persist team config

Write `~/.claude/teams/${TEAM_NAME}/config.json`:

```json
{
  "name": "<team-name>",
  "repo": "<repo-name>",
  "repo_root": "<absolute-path>",
  "profile": "<profile-name>",
  "base_branch": "<base-branch>",
  "work_branch": "<work-branch>",
  "epic": "<slug or null>",
  "spawned_at": "<ISO-8601 timestamp>",
  "members": [
    {
      "id": "<member-id>",
      "role": "<role>",
      "session_uuid": "<uuid>",
      "worktree_path": "<absolute-path>",
      "acked_at": "<ISO-8601 timestamp>"
    }
  ]
}
```

This file is squadkit-local state — never check it in. `mkdir -p` the parent directory before writing.

### 11. Hand off to the team-lead

Print a summary including:

- Team name and profile.
- Work branch (and whether it was cut as an epic).
- Roster: member id → role → worktree path.
- Path to the persisted config.
- The fact that `claude.flowkit.prBase` is pinned (if applicable) and how to clear it (`git config --unset claude.flowkit.prBase`).

Then send the team-lead its first dispatch prompt with the active roster.

## Constraints

- Never hardcode `develop` — always read `${BASE_BRANCH}` from `.squadkit/config.json` (default fallback only when the file is missing).
- Never spawn duplicate live members against an existing `~/.claude/teams/<name>/config.json`.
- Never create more than 5 builders, even if the user asks.
- Never invent a phonetic letter beyond `zulu` — stop and ask.
- Never write the team config before every member has acked.
- Worktrees live under `.claude/worktrees/<member>/` relative to the repo root, never an absolute scratch path.
- Singleton-builder profiles must not create worktrees (they share the workspace).

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:cut-epic` | Equivalent epic-cutting flow when run standalone. `spawn-team --epic` performs the same operation inline so the team is born on the epic branch. |
| `flowkit:preview-epic` | Run after the team has merged sub-PRs to preview the epic-to-`${BASE_BRANCH}` diff. |
| `flowkit:open-pr` / `flowkit:pr` | Member PRs target `claude.flowkit.prBase` automatically once the spawn pins it. |
| `swarmkit:swarm` | Independent fan-out for issue queues. Use `swarmkit` when work is already sliced into issues; use `spawn-team` when you want a coordinated long-running crew. |
