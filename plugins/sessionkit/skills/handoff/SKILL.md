---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Fast enough to run after every meaningful state change (PR opened, task completed, decision made) — not just when context is running low.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, TaskList, TaskGet, Skill, Agent
---

# Handoff

Capture the current session's goal, progress, git state, remaining work, and key context into `<working-dir>/.sessionkit/HANDOFF.md` so another agent can pick up without losing momentum.

This skill is optimized for **frequent invocation**. Run it after every meaningful state change — a PR opens, a task flips to `completed`, a key decision lands — not only when context is running low. The synthesis step is delegated to a Haiku sub-agent and skips sections whose inputs haven't changed since the last run, so the cost is small.

## Input

`$ARGUMENTS` — optional freeform notes to fold into the handoff (e.g. "focus on the auth refactor, skip the docs work"). If omitted, auto-infer everything from session state.

## Process

### 1. Gather context

Run these commands in parallel to collect raw data. Tolerate missing files — the absence of a todo file or uncommitted changes is itself signal.

```bash
cat .claude/TODO 2>/dev/null || cat .claude/todos.md 2>/dev/null || echo "No todo file"
git rev-parse HEAD 2>/dev/null || echo "no-head"
git branch --show-current
git diff --cached --name-only
git diff --name-only
git log --oneline -5
git diff --cached
```

Also invoke `TaskList` to get all task IDs, then call `TaskGet` once per task ID to fetch full details. Collect every task that is **not** deleted (i.e. `status !== "deleted"`). This runs in parallel with the bash commands above.

### 1a. Compute change fingerprints

Build two short fingerprints used in step 1c to decide which sections to regenerate:

- `gitFingerprint` — `<HEAD-sha>:<sorted-staged-files-hash>:<sorted-unstaged-files-hash>`. A change in HEAD or in the working-tree file lists invalidates the Git State + Progress sections.
- `taskFingerprint` — SHA-1 of the canonicalized (sorted by `id`, fields stripped to `id,subject,status,blockedBy`) Task List JSON. Any change invalidates the Task List + Remaining Work sections.

Compute both in shell (e.g. `git rev-parse HEAD`, `printf %s "$json" | shasum -a 1 | cut -d' ' -f1`).

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

### 1c. Skip-unchanged check

If `.sessionkit/HANDOFF.md` already exists, Read it and look for an HTML comment header of the form:

```
<!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->
```

Compare against the fingerprints from step 1a:

- If **both** match: nothing material has changed. Reuse the existing file's `## Git State`, `## Progress`, `## Task List`, and `## Remaining Work` sections verbatim — only refresh the `**Date**` field, `## Goal` (if `$ARGUMENTS` was passed), `## Context`, and `## Team State`. Skip the sub-agent call entirely; rewrite the file in-line. Report `(skip-unchanged: reused N sections)` in the confirmation.
- If only `gitFingerprint` matches: reuse `## Git State` and `## Progress`. Regenerate the rest.
- If only `taskFingerprint` matches: reuse `## Task List` and `## Remaining Work`. Regenerate the rest.
- If neither matches, or no prior file exists, or the meta header is absent: regenerate all sections.

### 2. Synthesize via Haiku sub-agent

Delegate markdown synthesis to a sub-agent running on Haiku. The handoff document is structured output and does not need the main model.

Invoke the `Agent` tool with:

- `subagent_type`: `"general-purpose"`
- `model`: `"claude-haiku-4-5"`
- `prompt`: a single message containing
  1. The fixed template from step 2a below.
  2. The conversation context summary (recent goal, decisions, gotchas — bullet form, no prose).
  3. The raw outputs from step 1 (git fingerprints, file lists, recent commits, todo file contents).
  4. The Task List JSON from step 1.
  5. The Team State JSON from step 1b (or `null`).
  6. Any sections from step 1c marked "reuse verbatim" with their existing content.
  7. `$ARGUMENTS` if present.
  8. Explicit instructions: "Emit ONLY the markdown document. No commentary, no fences around the whole thing. Use bullets, not paragraphs, for Progress / Remaining Work / Context. Preserve the JSON code blocks for Task List and Team State exactly as given."

**Timeout / failure handling**: if the Agent call fails, returns empty output, or produces output that does not contain the required `## Task List` heading, fall back to in-line synthesis. Prepend a single comment line to the document:

```
<!-- handoff-warning: haiku sub-agent unavailable, synthesized in-line -->
```

…and synthesize the document yourself using the same template.

### 2a. Strict template

The sub-agent (or in-line fallback) must emit exactly this structure. **Bullets only** in Progress / Remaining Work / Context — no narrative paragraphs. The meta header on line 1 is mandatory and is what step 1c reads on the next run.

```markdown
<!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->
# Handoff

**Project**: <working directory>
**Date**: <ISO date>
**Branch**: <current git branch>

## Goal
- <one bullet, one sentence>

## Progress
- <completed item>
- <decision made>
- <thread abandoned>

## Git State
- Branch: <branch>
- Staged: <list of staged files or "none">
- Unstaged: <list of unstaged files or "none">
- Recent commits (last 5):
  - <sha> <subject>

## Remaining Work
- <next step in priority order>
- <next step>

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
- <key decision>
- <gotcha>
- <external reference>
```

Inference rules (applied by the sub-agent):

- **Goal** — one bullet derived from branch name, recent commits, and conversation arc.
- **Progress** — bullets only: what's been completed, decided, or abandoned this session.
- **Remaining Work** — bullets in priority order, drawn from the todo file and unfinished conversation threads.
- **Task List** — serialize the tasks from step 1 as a single fenced `json` code block. Array of task objects. Include only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, `blocks`. Exclude `owner`, `metadata`, and deleted tasks. Empty array `[]` if none. Preserve original task `id` so `/pickup` can wire `blockedBy` relationships.
- **Team State** — emit **only** when step 1b matched a team. Single fenced `json` block with `teamName`, `leadAgentId`, `leadSessionId`, `members` (`{name, agentType, agentFile, cwd}` — `agentFile` optional). Omit the section entirely otherwise.
- **Context** — bullets only: decisions, gotchas, dead ends, external references. Keep to what the next agent genuinely needs.

If `$ARGUMENTS` is provided, weave its guidance into Goal or Context.

### 3. Write to disk

Check `.gitignore` coverage first:

```bash
test -f .gitignore && grep -qE '^\.sessionkit/?$' .gitignore && echo "covered" || echo "not-covered"
```

- **`.gitignore` absent**: ask "No `.gitignore` found. Create one with `.sessionkit/` to keep handoff docs out of version control? (yes/no)". On yes, write `.gitignore` containing only `.sessionkit/`. On no, proceed.
- **`.gitignore` present but not covered**: ask "`.gitignore` doesn't cover `.sessionkit/`. Append it? (yes/no)". On yes, append `.sessionkit/` to `.gitignore`. On no, proceed.
- **Already covered**: proceed silently.

If `.sessionkit/HANDOFF.md` already exists, Read it first (the Write tool requires a prior Read of the target path). Step 1c already did this when a prior file exists.

Then create the directory and write the file:

```bash
mkdir -p .sessionkit
```

Write the synthesized document to `.sessionkit/HANDOFF.md` using the Write tool, silently overwriting any existing file.

### 4. Confirm

Report the absolute path of the file written, the skip-unchanged status (e.g. `regenerated all sections` / `reused 4 sections, regenerated 2`), and suggest:

> Start a new session and run `/pickup` to resume.

## Constraints

- Run as soon as a meaningful state change happens — frequent handoffs are cheap by design (skip-unchanged + Haiku sub-agent)
- Bullets only in Progress, Remaining Work, and Context — no prose paragraphs
- The `<!-- handoff-meta ... -->` header on line 1 is mandatory; step 1c reads it on the next run to decide what to skip
- `.sessionkit/HANDOFF.md` in the working directory is the canonical location — never write elsewhere
- Section order in HANDOFF.md is fixed: Goal → Progress → Git State → Remaining Work → Task List → Team State (optional) → Context
- Legacy HANDOFFs that lack a `## Task List`, `## Team State`, or meta header remain valid inputs to `/pickup` — their absence is not an error (the next run will simply regenerate everything)
- The `## Team State` section is omitted when no team config in `~/.claude/teams/` matches the current session by `leadSessionId` or member `cwd`
- Always Read `.sessionkit/HANDOFF.md` before overwriting it with Write — the Write tool refuses to overwrite paths it hasn't read in the current conversation
- If the Haiku sub-agent fails, fall back to in-line synthesis and prepend a `<!-- handoff-warning: ... -->` line so the user knows the slow path was taken
