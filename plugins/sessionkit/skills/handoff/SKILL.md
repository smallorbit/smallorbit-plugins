---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Run it when context is running low or after completing a meaningful chunk of work.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, TaskList, TaskGet, AskUserQuestion
---

# Handoff

## Input

`$ARGUMENTS` — optional freeform notes to fold into Goal or Context (e.g. "focus on the auth refactor, skip the docs work"). If omitted, auto-infer everything from session state.

## Process

### 1. Fold arguments

If `$ARGUMENTS` is non-empty, incorporate the freeform text into Goal or Context where it fits naturally. No flags are recognized.

### 2. Summarize conversation context

Derive the following from the live session — keep everything as bullets, no prose:

- **Goal** — one bullet: what this session is fundamentally trying to accomplish.
- **Progress** — what was completed, decided, or abandoned this session.
- **Remaining Work** — what still needs doing, in priority order.
- **Context** — key decisions, gotchas, dead ends, external references the next agent needs.

### 3. Gather the task list

Call `TaskList`, then `TaskGet` once per task ID. Collect every task whose `status` is not `"deleted"` and serialize to a JSON array. Each object MUST include only these fields:

```
id, subject, description, activeForm, status, blockedBy, blocks
```

Use `[]` for `blockedBy` / `blocks` when empty. Preserve the original task `id` so `/pickup` can rewire `blockedBy` relationships.

### 4. Resolve `.gitignore` coverage

Check coverage:

```bash
test -f .gitignore && grep -qE '^\.sessionkit/?$' .gitignore && echo "covered" || echo "not-covered"
```

- **`.gitignore` absent**: ask via `AskUserQuestion` — "No `.gitignore` found. Create one with `.sessionkit/` to keep handoff docs out of version control?". On yes, write `.gitignore` containing only `.sessionkit/`. On no, proceed.
- **`.gitignore` present but not covered**: ask via `AskUserQuestion` — "`.gitignore` doesn't cover `.sessionkit/`. Append it?". On yes, append `.sessionkit/`. On no, proceed.
- **Already covered**: proceed silently.

### 5. Write the document

Run `mkdir -p .sessionkit`, then `Write` the document to `.sessionkit/HANDOFF.md` using the template below. Report the absolute path and suggest:

> Start a new session and run `/pickup` to resume.

## Document template

```markdown
# Handoff

## Goal
- <one bullet, one sentence>

## Progress
- <completed item or decision>

## Remaining Work
- <next step in priority order>

## Context
- <key decision, gotcha, or external reference>

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
```

**Constraints:**
- Sections MUST appear in this exact order: Goal → Progress → Remaining Work → Context → Task List.
- Progress, Remaining Work, and Context MUST contain bullets only — no narrative paragraphs.
- The Task List section MUST contain exactly one fenced `json` block. Emit `[]` if there are no tasks.
- Do NOT write any other files or sections beyond what the template specifies.
