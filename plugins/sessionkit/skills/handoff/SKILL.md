---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Use when context is running low.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write
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

## Context
Key decisions made, gotchas encountered, important notes the next agent must know.
```

Inference rules:
- **Goal** — derive from branch name, recent commits, and the arc of the conversation.
- **Progress** — what's been completed, decided, or abandoned this session.
- **Remaining Work** — pull from the todo file and from any unfinished threads in the conversation; order by priority.
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
