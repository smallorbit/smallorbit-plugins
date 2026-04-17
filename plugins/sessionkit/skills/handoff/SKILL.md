---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Use when context is running low.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Handoff

Capture the current session's goal, progress, git state, remaining work, and key context into `<working-dir>/.claude/HANDOFF.md` so another agent can pick up without losing momentum.

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

### 3. Present for approval

Show the drafted document inline. Then ask:

> Does this look right? Say 'yes' to write it, or edit any sections first.

Do not write anything until the user explicitly approves.

### 4. Write to disk

On approval:

```bash
mkdir -p .claude
```

If `.claude/HANDOFF.md` already exists, warn the user and ask whether to overwrite before proceeding.

Write the approved document to `.claude/HANDOFF.md` using the Write tool.

### 5. Confirm

Report the absolute path of the file written and suggest:

> Start a new session and run `/pickup` to resume.

## Constraints

- Never write the file without explicit user approval
- Keep the document concise — it's a recall aid, not full documentation
- `.claude/HANDOFF.md` in the working directory is the canonical location — never write elsewhere
- If `.claude/HANDOFF.md` already exists, warn before overwriting
