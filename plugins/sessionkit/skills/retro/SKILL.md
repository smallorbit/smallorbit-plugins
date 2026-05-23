---
name: retro
description: Run a session retrospective — scan conversation transcript, task list, git activity, and hook/tool-denial events, then surface what went well and what didn't, and turn the findings into a one-keystroke action menu that delegates to the right downstream skill.
triggers:
  - "/retro"
  - "reflect on this session"
  - "run a retrospective"
  - "session retrospective"
  - "what went well this session"
  - "retrospective"
allowed-tools: Bash, Read, Glob, Grep, TaskList, TaskGet, AskUserQuestion, Skill
---

# Retro

Run a lightweight session retrospective. Scan four input surfaces — conversation transcript, task list, git activity, and hook/tool-denial events — then produce an inline markdown summary and a one-keystroke action menu that delegates findings to the right downstream skill.

Output stays entirely inline. No files are written.

## Process

### 1. Gather raw signals

Run all data-collection commands in parallel. Tolerate missing outputs gracefully — an empty surface is itself a signal.

**Git activity within the session window**

```bash
git log --oneline --since="8 hours ago" 2>/dev/null || echo "no git history"
git branch --show-current 2>/dev/null || echo "no branch"
git stash list 2>/dev/null | head -5
gh pr list --author "@me" --state all --limit 10 --json number,title,state,createdAt 2>/dev/null || echo "no gh cli"
```

**Session JSONL files — tool-denial and hook-blocked events**

```bash
PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g')
ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -3
```

Read the most recent JSONL file(s) and scan for:
- Lines where `type` is `tool_result` and the content contains `permission denied`, `tool denied`, `hook blocked`, or similar rejection vocabulary.
- Lines where the user corrected Claude mid-turn (e.g. overrides, "no, actually", "wait", repeated re-prompting).

**Task list**

Invoke `TaskList` to get all task IDs. Then call `TaskGet` for each task ID in parallel to fetch full details. Collect every task that is not deleted (`status !== "deleted"`).

**Conversation transcript**

Review the conversation history in context for:
- Repeated instructions or corrections (user had to re-say the same thing).
- Friction moments — commands that failed and were retried, back-and-forth loops.
- Successful workflows — patterns that worked cleanly without correction.
- Mistakes caught mid-flight — self-corrections, reverted edits, wrong-path detours.

### 2. Synthesize findings

Organize raw signals into three buckets. Be specific and concrete — cite turns, PR numbers, file names, or task subjects where applicable.

**What went well** (2–5 bullets)
- Patterns that worked without friction.
- Cleanly executed workflows.
- Mistakes caught early before they propagated.

**What didn't go well** (2–5 bullets, or an explicit empty-state line)
- Repeated corrections or re-prompts.
- Hook-blocked or tool-denied actions.
- Commands that failed and required diagnosis.
- Tasks that stalled or required scope revision.
- If no friction surfaces at all, emit: _No friction observed this session._

**Recommended actions** (1–4 items, capped at 4)

For each friction signal or repeatable pattern, identify the most useful downstream action and its delegation target:

| Pattern | Delegation target |
|---------|------------------|
| Repeated command sequence worth automating | `sessionkit:skillit` |
| Repeated permission approvals | `sessionkit:suggest-permissions` |
| Context running low or session should be captured | `sessionkit:handoff` |
| Recurring hook-blocked behavior worth enforcing | `hookify:hookify` |
| A problem worth filing as a tracked issue | `speckit:issue` |
| A behavioral config worth persisting | `update-config` |
| No matching skill | Surface as plain-text guidance only |

Cap the list at 4 options. If more than 4 items qualify, keep the highest-signal ones. Reserve the 4th option slot for "Other — I'll handle this manually" when there is remaining guidance that doesn't map to a skill.

### 3. Emit inline output

Print the three sections as markdown directly in the turn. Do not write any file.

```markdown
## What went well

- <specific bullet referencing a turn, PR, file, or task>
- ...

## What didn't go well

- <specific bullet, or "No friction observed this session.">
- ...

## Recommended actions

1. <Action description> — Delegates to `/<skill>`
2. ...
```

### 4. Present the action menu

After the markdown sections, call `AskUserQuestion` with:

- `question`: "Which of these would you like to action now?"
- `options`: one option per recommended action, each with:
  - `label`: short action title (e.g. "Encode worktree-cleanup pattern as a skill")
  - `description`: names the concrete delegation target if applicable (e.g. "Delegates to `/skillit`"), or "Manual — guidance only" if no skill applies.
- `multiSelect: true`
- Include a final option: `{ label: "None — I'm done", description: "Skip all actions and close the retro." }`

Do not proceed to step 5 until the user answers via `AskUserQuestion`. Never act on recommendations without explicit user selection.

### 5. Execute selected actions

Announce the actions that will be executed in order:

> Running: <action 1>, then <action 2>, ...

Then invoke each selected skill one at a time using the `Skill` tool, passing the skill's name from the delegation target column in step 2. Pass any relevant context from the retro findings as arguments where the target skill accepts them.

For options the user selected that carry no delegation target (plain-text guidance), surface them as a brief summary after the skill invocations complete.

If the user selects "None — I'm done", skip all invocations and close the retro with a one-line acknowledgement.

## Constraints

- **Never write files.** Output is inline only — no retro file, no `.sessionkit/RETRO.md`, no artifact of any kind.
- **Always identify at least one item per `## What went well` and `## What didn't go well`** before falling back to the empty-state message. If the transcript is genuinely featureless, emit "No friction observed this session." for the second section and a single concrete positive for the first (e.g. the session completed without errors).
- **Never run delegated skills without explicit user selection.** The `AskUserQuestion` call in step 4 is mandatory. Skipping it and auto-running skills is a defect.
- **Cap recommended actions at 4** to fit `AskUserQuestion`'s option limit. The 4th slot is reserved for "Other — I'll handle this manually" when excess items exist.
- **`retro` is a thin reflective layer.** It does not absorb `skillit`'s encoding logic. When retro recommends "encode X as a skill," it delegates to `skillit` — it does not author the skill file itself.
- **Do not modify `skillit` or any other existing skill.** Retro delegates to them; it does not replace or extend them.
