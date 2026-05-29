---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Run it after every meaningful state change (PR opened, task completed, decision made) — delta mode keeps the cost trivial so you don't have to wait for context pressure.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, TaskList, TaskGet, AskUserQuestion, Skill, Agent
---

# Handoff

## Input

`$ARGUMENTS` — optional freeform notes to fold into the handoff (e.g. "focus on the auth refactor, skip the docs work"). If omitted, auto-infer everything from session state.

Recognized flags (parsed from `$ARGUMENTS`):

- `--full` — force the full-regenerate path even if delta mode would otherwise apply. Use when you want a fresh narrative pass (e.g. Goal/Context have meaningfully drifted but the structural fingerprints haven't).

If `--full` is present, strip it from `$ARGUMENTS` before folding the remaining text into Goal/Context.

## Execution model

Handoff runs its synthesis on Haiku regardless of the session's active model — the document is structured output and Haiku is materially faster for it. The work is split:

- **Outer tier (this skill, any model)** — does what the live session is uniquely able to do or what must reach the user: summarize the conversation arc, gather the task list (a sub-agent's `TaskList`/`TaskGet` see a different task store, not this session's — see step 2.5), and resolve the user-facing `.gitignore` prompt.
- **Haiku sub-agent** — gathers git state, computes fingerprints, decides delta vs full, and writes the document to disk, using the task JSON the outer tier hands it.

The outer tier MUST pass full self-contained instructions to the sub-agent inline. It MUST NOT tell the sub-agent to "run the handoff skill" or reference this skill by name — that would re-trigger the skill and recurse.

## Process

### 1. Parse arguments

Detect and strip `--full` from `$ARGUMENTS`. Keep the remaining freeform text for step 2.

### 2. Summarize conversation context

Produce the bullets only the live session can derive — the sub-agent has no view of this conversation. Keep them tight (bullets, no prose):

- **Goal** — one bullet: what this session is fundamentally trying to accomplish.
- **Progress** — what was completed, decided, or abandoned this session.
- **Context** — key decisions, gotchas, dead ends, external references the next agent needs.

Fold the remaining `$ARGUMENTS` text into Goal or Context where it fits. This summary becomes an input to the sub-agent in step 4.

### 2.5. Gather the task list (outer tier)

Call `TaskList`, then `TaskGet` once per task ID. Collect every task whose `status !== "deleted"` and serialize them to a JSON array containing only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, `blocks` (empty array `[]` if none). This becomes the `taskListJson` input to the sub-agent in step 4.

This MUST run in the outer tier: a sub-agent's `TaskList`/`TaskGet` resolve to a different task store and will not return this session's tasks — passing the serialized JSON as data is the only reliable way to capture the live task list.

### 3. Resolve `.gitignore` coverage (outer tier — user-facing)

Check coverage:

```bash
test -f .gitignore && grep -qE '^\.sessionkit/?$' .gitignore && echo "covered" || echo "not-covered"
```

- **`.gitignore` absent**: ask via `AskUserQuestion` "No `.gitignore` found. Create one with `.sessionkit/` to keep handoff docs out of version control?". On yes, write `.gitignore` containing only `.sessionkit/`. On no, proceed.
- **`.gitignore` present but not covered**: ask via `AskUserQuestion` "`.gitignore` doesn't cover `.sessionkit/`. Append it?". On yes, append `.sessionkit/`. On no, proceed.
- **Already covered**: proceed silently.

This stays in the outer tier because a sub-agent cannot prompt the user.

### 4. Dispatch the Haiku sub-agent

Invoke the `Agent` tool with:

- `subagent_type`: `"general-purpose"`
- `model`: `"haiku"`
- `prompt`: a single self-contained message containing (a) the conversation summary from step 2, (b) the `taskListJson` from step 2.5, (c) the `--full` flag state, and (d) the verbatim operating instructions below. Do not reference this skill by name anywhere in the prompt.

> You are writing a session handoff document to `.sessionkit/HANDOFF.md`. Follow these steps exactly and report the outcome. Do not ask the user anything — you have no user access. The task list has been gathered for you and provided as `taskListJson`; do NOT call `TaskList` or `TaskGet` yourself — your task context differs from the session's, so those tools would return the wrong tasks.
>
> **A. Gather git state.** Run in parallel:
> ```bash
> git rev-parse HEAD 2>/dev/null || echo "no-head"
> git branch --show-current
> git diff --cached --name-only
> git diff --name-only
> git log --oneline -5
> git diff --cached
> ```
> Use the provided `taskListJson` as the task list — it already excludes deleted tasks.
>
> **B. Compute fingerprints.**
> - `gitFingerprint` = `<HEAD-sha>:<sorted-staged-files-hash>:<sorted-unstaged-files-hash>`.
> - `taskFingerprint` = SHA-1 of the canonicalized `taskListJson` (sorted by `id`, fields stripped to `id,subject,status,blockedBy`). Compute via `printf %s "$json" | shasum -a 1 | cut -d' ' -f1`.
>
> **C. Skip-unchanged check.** If `.sessionkit/HANDOFF.md` exists, Read it and find the first-line meta header `<!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->`. Compare with two independent reuse decisions:
> - `gitFingerprint` matches → reuse `## Git State` and `## Progress` verbatim, else regenerate them.
> - `taskFingerprint` matches → reuse `## Task List` and `## Remaining Work` verbatim, else regenerate them.
> `## Goal` and `## Context` are always taken from the conversation summary provided to you. If no prior file or no meta header, regenerate all sections.
>
> **D. Delta-vs-full decision.** Use the **delta** path when ALL hold: (1) a prior file parsed cleanly (meta header, all six canonical sections in order, `## Task List` json block parses); (2) the prior HEAD-sha is an ancestor of current HEAD — `git merge-base --is-ancestor <prior-head-sha> HEAD` exits 0; (3) at most two of the four reusable sections need regeneration; (4) `--full` was not passed. Otherwise use the **full** path.
>
> **E-delta. Delta mechanics.** Surgically Edit the existing file: refresh `## Goal` and `## Context` from the conversation summary; regenerate only the flagged reusable sections; update the meta header's `gitFingerprint` / `taskFingerprint` to the step-B values and refresh `**Date**`; leave verbatim-reuse sections byte-exact.
>
> **E-full. Full mechanics.** `mkdir -p .sessionkit` and Write the whole document per the template below.
>
> **F. Template** (emit exactly this structure; bullets only in Progress / Remaining Work / Context; meta header on line 1 is mandatory):
> ````markdown
> <!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->
> # Handoff
>
> **Project**: <working directory>
> **Date**: <ISO date>
> **Branch**: <current git branch>
>
> ## Goal
> - <one bullet, one sentence>
>
> ## Progress
> - <completed item>
> - <decision made>
> - <thread abandoned>
>
> ## Git State
> - Branch: <branch>
> - Staged: <list of staged files or "none">
> - Unstaged: <list of unstaged files or "none">
> - Recent commits (last 5):
>   - <sha> <subject>
>
> ## Remaining Work
> - <next step in priority order>
> - <next step>
>
> ## Task List
> ```json
> [
>   {
>     "id": "<task-id>",
>     "subject": "<subject>",
>     "description": "<description>",
>     "activeForm": "<activeForm>",
>     "status": "<status>",
>     "blockedBy": [],
>     "blocks": []
>   }
> ]
> ```
>
> ## Context
> - <key decision>
> - <gotcha>
> - <external reference>
> ````
>
> **G. Inference rules.**
> - **Progress** — bullets from staged/unstaged file lists, recent commits, plus the conversation summary's progress bullets.
> - **Remaining Work** — bullets in priority order from the Task List plus unfinished threads in the conversation summary.
> - **Task List** — emit `taskListJson` as one fenced `json` block, preserving each task's original `id` so pickup can rewire `blockedBy`. It is already filtered to the right fields and excludes deleted tasks; emit `[]` if it is empty.
> - **Goal** / **Context** — take from the conversation summary provided to you.
>
> **H. Report back.** Return one line stating the chosen mode and reuse outcome, e.g. `delta — refreshed Goal/Context, regenerated Git State + Progress` or `full — regenerated all sections`. Confirm the document was written to `.sessionkit/HANDOFF.md`.

**Fallback**: if the Agent call fails, returns empty output, or the file it wrote is missing the `## Task List` heading, synthesize the document yourself inline using the same template, prepend `<!-- handoff-warning: haiku sub-agent unavailable, synthesized in-line -->`, and write it to `.sessionkit/HANDOFF.md`.

### 5. Report

Relay the sub-agent's reported mode and reuse outcome, state the absolute path of the written file, and suggest:

> Start a new session and run `/pickup` to resume.
