# Sessionkit

A Claude Code plugin for session continuity, context handoffs, and meta-learning. Pick up exactly where you left off, discover reusable skills from your work, and keep permission prompts from slowing you down.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install sessionkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/sessionkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **handoff** | `/handoff` | Captures session goal, progress, git state, remaining work, active tasks, and (when present) multi-agent team state into `.sessionkit/HANDOFF.md`. Use when context is running low or when switching agents. |
| **pickup** | `/pickup` | Loads `.sessionkit/HANDOFF.md` at the start of a new session, orients the agent, hydrates pending/in-progress tasks back into the task system, and auto-restores team role context when a `## Team State` block is present. |
| **skillit** | `/skillit` | Reflects on the current session to identify patterns worth encoding as reusable skills. Checks for existing overlap before proposing anything new. |
| **suggest-permissions** | `/suggest-permissions` | Scans recent session history for repeatedly approved permissions and proposes additions to `.claude/settings.json` to reduce future prompts. |

### Sub-Skills (internal)

| Skill | Used by | Purpose |
|-------|---------|---------|
| **get-session-id** | suggest-permissions, handoff, pickup | Resolves the current Claude Code session UUID from `~/.claude/projects/`. |

## Typical Workflows

### Handing off between sessions

```
/handoff                          # Capture current state before context runs out
                                  # — start a new Claude Code session —
/pickup                           # Restore context and resume work
```

### Growing your skill library

```
/skillit                          # After an interesting session — what's worth keeping?
```

### Reducing permission noise

```
/suggest-permissions              # After a few sessions — what do I keep approving?
```

## How Handoff / Pickup Works

`/handoff` collects git state, todo files, conversation history, and the active task list, synthesizes them into a structured document, prints it inline, then writes it immediately to `.sessionkit/HANDOFF.md` — no approval step. The only prompt is a one-time confirmation before adding `.sessionkit/` to `.gitignore`, if the entry is not already present.

`/pickup` reads that document at the start of a fresh session, produces an orientation summary — goal, progress, git state, remaining work, and key context — and hydrates any serialized tasks back into the task system via `TaskCreate` and `TaskUpdate`.

The two skills are intentionally separate: handoff writes, pickup reads. The handoff file is never modified or deleted by pickup.

### Task Round-Trip

`/handoff` snapshots every non-deleted task into a `## Task List` fenced JSON block inside `HANDOFF.md`. `/pickup` reads that block and recreates the tasks in the new session.

**What survives the round-trip** (fields preserved verbatim):

| Field | Notes |
|-------|-------|
| `id` | Carried in the snapshot to allow `blockedBy` rewiring; the new session assigns a fresh ID |
| `subject` | Task title |
| `description` | Full task description |
| `activeForm` | The task's active form/view state |
| `status` | Original status (`pending` or `in_progress`) — all recreated tasks start as `pending` |
| `blockedBy` | Dependency edges; remapped to new IDs after all tasks are created |
| `blocks` | Listed in the snapshot for reference; not re-wired (the inverse of `blockedBy` is implicit) |

**What is not preserved**: `owner`, `metadata`.

**Which tasks are restored**: only tasks with `status` of `pending` or `in_progress`. Completed tasks appear in the orientation summary as history but are not recreated.

**Back-compat**: legacy `HANDOFF.md` files that were written before task-list support was added (i.e. no `## Task List` section) are fully valid. `/pickup` emits one warning line — `No task list snapshot — skipping hydration` — and continues with the orientation summary.

### Team State Round-Trip

When the current session is part of a multi-agent team — i.e. a config file under `~/.claude/teams/<team>/config.json` matches by `leadSessionId` or member `cwd` — `/handoff` emits a `## Team State` fenced JSON block capturing the team identity and member roster:

```json
{
  "teamName": "...",
  "leadAgentId": "...",
  "leadSessionId": "...",
  "members": [
    {"name": "team-lead", "agentType": "lead", "agentFile": "...", "cwd": "..."}
  ]
}
```

`/pickup` parses the block, identifies which member corresponds to the resuming session (by `cwd` match, or by lead-session-id match for the lead role), reads the member's `agentFile` if present, and surfaces one orientation line:

> Active team `<name>` detected (role: <agentType>). Loaded role context from `<agentFile>`.

When no team is active, the section is omitted entirely. Handoffs without a `## Team State` section are valid — `/pickup` simply skips the team-restore step.

## Handoff Document Structure

`.sessionkit/HANDOFF.md` is a structured Markdown file with these sections, in order:

| Section | Contents |
|---------|----------|
| **Goal** | One or two sentences describing what this session is working toward |
| **Progress** | Bullet list of completed steps and key decisions made |
| **Git State** | Current branch, staged/unstaged files, recent commits |
| **Remaining Work** | Prioritized list of what still needs to be done |
| **Task List** | Fenced JSON array of task objects (see Task Round-Trip above) |
| **Team State** | *(optional)* Fenced JSON object capturing active team identity and members (see Team State Round-Trip above). Omitted when no team is active. |
| **Context** | Gotchas, constraints, or non-obvious state the next agent must know |

You can manually edit `.sessionkit/HANDOFF.md` between sessions — `/pickup` reads whatever is there.

## How Skillit Works

At the end of a session, `/skillit` reviews the conversation for:

- Repeated instructions or corrections you gave Claude
- Multi-step workflows executed in a fixed pattern
- Heuristics applied consistently

It scans your existing skill library for overlap before proposing anything new, then offers to create a new skill or extend an existing one — with your approval before writing anything.

## How Suggest Permissions Works

`/suggest-permissions` reads recent session `.jsonl` files from `~/.claude/projects/` and identifies Bash commands, file edit paths, and MCP tools you approved multiple times. It proposes a `permissions.allow` block for `.claude/settings.json` with a one-line rationale for each entry, and only writes changes after you approve.

## Pairing with Other Plugins

Sessionkit works alongside every plugin in the suite:

**With [swarmkit](../swarmkit)**
- Use `/skillit` after a swarm run to capture reusable patterns that emerged
- Use `/handoff` before context runs out mid-swarm to preserve state for the next agent

**With [speckit](../speckit)**
- Use `/speckit:interview` as a planning warm-up before `/spec` — arrive with clearer requirements
- `/handoff` is useful if a `/spec` session runs long and needs to continue in a new context

**With [flowkit](../flowkit)**
- Use `/handoff` before a long `/release` or `/cut` session if context is running low
- `/skillit` after a release helps capture any new conventions or one-off scripts worth keeping
