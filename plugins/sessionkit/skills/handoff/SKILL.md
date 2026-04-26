---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Use when context is running low.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, TaskList, TaskGet, Skill
---

# Handoff

Capture the current session's goal, progress, git state, remaining work, and key context into `<working-dir>/.sessionkit/HANDOFF.md` so another agent can pick up without losing momentum.

Use when context is running low, when switching machines or sessions, or whenever you want a clean baton-pass to a fresh agent.

## Input

`$ARGUMENTS` — optional freeform notes to fold into the handoff (e.g. "focus on the auth refactor, skip the docs work"). If omitted, auto-infer everything from session state.

## Process

### 1. Gather context

Run these commands in parallel to collect raw data. Tolerate missing files — the absence of a todo file or uncommitted changes is itself signal.

```bash
cat .claude/TODO 2>/dev/null || cat .claude/todos.md 2>/dev/null || echo "No todo file"
git branch --show-current
git diff --cached --name-only
git diff --name-only
git log --oneline -5
git diff --cached
```

Also invoke `TaskList` to get all task IDs, then call `TaskGet` once per task ID to fetch full details. Collect every task that is **not** deleted (i.e. `status !== "deleted"`). This runs in parallel with the bash commands above.

### 1b. Detect active team

Check `~/.claude/teams/*/config.json` for a team config that matches the current session. A team matches if either:

1. Its `leadSessionId` equals the current session ID (resolved via `sessionkit:get-session-id`), OR
2. Any member's `cwd` equals `$PWD`.

```bash
CURRENT_SID="$(PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g'); ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -1 | xargs -r basename -s .jsonl)"
ls ~/.claude/teams/*/config.json 2>/dev/null | while read CFG; do
  jq -r --arg sid "$CURRENT_SID" --arg cwd "$PWD" '
    if (.leadSessionId == $sid) or (any(.members[]?; .cwd == $cwd))
    then "MATCH:" + input_filename
    else empty
    end
  ' "$CFG"
done
```

If a team matches, read its `config.json` and extract: `name`, `leadAgentId`, `leadSessionId`, and the `members` array. Drop runtime-only fields from each member (keep only `name`, `agentType`, `agentFile`, `cwd`). If `agentFile` is absent on a member, omit the field. If no team matches, skip the Team State section entirely in step 2.

### 2. Draft the document

Synthesize the collected data plus conversation history into this exact structure:

```markdown
# Handoff

**Project**: <working directory>
**Date**: <ISO date>
**Branch**: <current git branch>

## Goal
What we were trying to accomplish this session.

## Progress
How far we got — what's been completed, what's been decided.

## Git State
- Branch: <branch>
- Staged: <list of staged files or "none">
- Unstaged: <list of unstaged files or "none">
- Recent commits (last 5): <list>

## Remaining Work
Outstanding todos and next steps in priority order.

## Task List
```json
[
  {
    "id": "<task-id>",
    "subject": "<subject>",
    "description": "<description>",
    "activeForm": "<activeForm>",
    "status": "<status>",
    "blockedBy": [],
    "blocks": []
  }
]
```

## Team State
```json
{
  "teamName": "<name>",
  "leadAgentId": "<leadAgentId>",
  "leadSessionId": "<leadSessionId>",
  "members": [
    {"name": "<name>", "agentType": "<type>", "agentFile": "<path>", "cwd": "<path>"}
  ]
}
```

## Context
Key decisions made, gotchas encountered, important notes the next agent must know.
```

Inference rules:
- **Goal** — derive from branch name, recent commits, and the arc of the conversation.
- **Progress** — what's been completed, decided, or abandoned this session.
- **Remaining Work** — pull from the todo file and from any unfinished threads in the conversation; order by priority.
- **Task List** — serialize the tasks collected in step 1 as a single fenced `json` code block. The JSON is an array of task objects. Include only these fields: `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, `blocks`. Exclude `owner`, `metadata`, and any deleted tasks. If no tasks exist, write an empty array `[]`. The `id` field preserves the original task ID so `/pickup` can wire `blockedBy` relationships in a follow-up pass.
- **Team State** — emit this section **only** when step 1b matched a team. Serialize the matched team as a single fenced `json` code block with these fields: `teamName`, `leadAgentId`, `leadSessionId`, and `members` (array of `{name, agentType, agentFile, cwd}` — `agentFile` optional). Omit the section entirely if no team matched.
- **Context** — decisions, gotchas, dead ends, external references. Keep it to what the next agent genuinely needs.

If `$ARGUMENTS` is provided, weave its guidance into the relevant sections (often Goal or Context).

### 3. Present the draft

Show the drafted document inline in the conversation so the user can see what will be written. Then proceed immediately to step 4 — no approval needed.

### 4. Write to disk

Check `.gitignore` coverage first:

```bash
test -f .gitignore && grep -qE '^\.sessionkit/?$' .gitignore && echo "covered" || echo "not-covered"
```

- **`.gitignore` absent**: ask "No `.gitignore` found. Create one with `.sessionkit/` to keep handoff docs out of version control? (yes/no)". On yes, write `.gitignore` containing only `.sessionkit/`. On no, proceed.
- **`.gitignore` present but not covered**: ask "`.gitignore` doesn't cover `.sessionkit/`. Append it? (yes/no)". On yes, append `.sessionkit/` to `.gitignore`. On no, proceed.
- **Already covered**: proceed silently.

If `.sessionkit/HANDOFF.md` already exists, Read it first (the Write tool requires a prior Read of the target path). If the file doesn't exist yet, skip this step.

Then create the directory and write the file:

```bash
mkdir -p .sessionkit
```

Write the document to `.sessionkit/HANDOFF.md` using the Write tool, silently overwriting any existing file.

### 5. Confirm

Report the absolute path of the file written and suggest:

> Start a new session and run `/pickup` to resume.

## Constraints

- After presenting the draft, write it immediately — do not pause for approval
- Keep the document concise — it's a recall aid, not full documentation
- `.sessionkit/HANDOFF.md` in the working directory is the canonical location — never write elsewhere
- Section order in HANDOFF.md is fixed: Goal → Progress → Git State → Remaining Work → Task List → Team State (optional) → Context
- Legacy HANDOFFs that lack a `## Task List` or `## Team State` section remain valid inputs to `/pickup` — their absence is not an error
- The `## Team State` section is omitted when no team config in `~/.claude/teams/` matches the current session by `leadSessionId` or member `cwd`
- Always Read `.sessionkit/HANDOFF.md` before overwriting it with Write — the Write tool refuses to overwrite paths it hasn't read in the current conversation
