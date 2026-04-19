---
name: exp-swarm-teams
description: "EXPERIMENTAL — requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1. Spawn parallel agents for GitHub issues using the Agent Teams API instead of isolated worktrees. Same arg grammar as swarmkit:swarm. See epic #285 and https://code.claude.com/docs/en/agent-teams."
---

# exp-swarm-teams Skill (Experimental)

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

## Constraints

- This skill is experimental and subject to breaking changes as the Agent Teams API evolves
- Never fall through to `swarmkit:swarm` — if the preflight fails, abort
- Never merge into `main` directly — all PRs target the base branch (`develop` by default)
- Commit messages must follow `conventional-commit-message` sub-skill format
- Never mention Claude or add co-author lines in commit messages
- Every PR must reference the issue it closes (`Closes #N`)
