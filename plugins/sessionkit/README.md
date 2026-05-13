# Sessionkit

A Claude Code plugin for session continuity, context handoffs, and meta-learning. Pick up exactly where you left off, discover reusable skills from your work, and keep permission prompts from slowing you down.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers the plan → execute → ship loop and where sessionkit fits in.

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
| **handoff** | `/handoff` | Captures session goal, progress, git state, remaining work, and active tasks into `.sessionkit/HANDOFF.md`. Use when context is running low or when switching agents. |
| **pickup** | `/pickup` | Loads `.sessionkit/HANDOFF.md` at the start of a new session, orients the agent, and hydrates pending/in-progress tasks back into the task system. |
| **roadmap** | `/roadmap` | Surveys the current work-in-flight and produces an approved task chain that takes it all the way to "shipped". On approval, optionally hands off to `/drive` for autonomous execution. |
| **drive** | `/drive` | Executes an approved task chain autonomously — marks each task in_progress before starting and completed immediately after, surfaces only for blockers or executive decisions. Pairs with `/roadmap`; standalone-invokable when a task list is already prepared. |
| **skillit** | `/skillit` | Reflects on the current session to identify patterns worth encoding as reusable skills. Checks for existing overlap before proposing anything new. |
| **suggest-permissions** | `/suggest-permissions` | Scans recent session history for repeatedly approved permissions and proposes additions to `.claude/settings.json` to reduce future prompts. |
| **retro** | `/retro` | Runs a session retrospective — scans conversation transcript, task list, git activity, and hook/tool-denial events, then surfaces what went well and what didn't, and presents a one-keystroke action menu that delegates to the right downstream skill. |

## Typical Workflows

### Handing off between sessions

```
/handoff                          # Capture current state before context runs out
                                  # — start a new Claude Code session —
/pickup                           # Restore context and resume work
```

### Planning the path to "done", then driving it

```
/roadmap                          # Survey work-in-flight, propose a task chain to ship,
                                  # ask for approval

# On approval, either:
/drive                            # Hand the chain to Claude — it executes autonomously
                                  # and only surfaces for blockers or executive decisions

# …or work the task list manually if you'd rather drive it yourself.
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

### Team Coordination

Multi-agent team coordination is owned by [squadkit](../squadkit). Squadkit ships a `SessionStart` hook that reads `~/.claude/teams/*/config.json` directly and re-emits the active role contract whenever a session starts — including sessions resumed via `/pickup`. Sessionkit therefore stays orthogonal: it captures generic session state, and squadkit layers team-role context on top.

Handoff files written by sessionkit ≤ 1.5.0 may contain a legacy squad-coordination section. `/pickup` ignores it silently — it's an inert artifact, not a parse error. Role-context restoration now lives in [squadkit](../squadkit)'s `SessionStart` hook.

## Handoff Document Structure

`.sessionkit/HANDOFF.md` is a structured Markdown file with these sections, in order:

| Section | Contents |
|---------|----------|
| **Goal** | One or two sentences describing what this session is working toward |
| **Progress** | Bullet list of completed steps and key decisions made |
| **Git State** | Current branch, staged/unstaged files, recent commits |
| **Remaining Work** | Prioritized list of what still needs to be done |
| **Task List** | Fenced JSON array of task objects (see Task Round-Trip above) |
| **Context** | Gotchas, constraints, or non-obvious state the next agent must know |

You can manually edit `.sessionkit/HANDOFF.md` between sessions — `/pickup` reads whatever is there.

## How Roadmap / Drive Works

`/roadmap` surveys the current work-in-flight — uncommitted state, current branch's role (feature / epic / RC / develop), open PRs targeting common bases, peer PRs in a stack, in-flight worktrees, RC branches awaiting release, the latest release tag, and the existing task list. It classifies the state, picks the matching sub-chain from a step library (commit → push → PR → review → merge → bump → cut → release), and materializes it as a linear task chain with `blockedBy` edges wired between steps.

After the plan is built, `/roadmap` presents a compact summary and asks for approval via `AskUserQuestion`:

- **Drive it for me** — hands the chain to `/drive` for autonomous execution.
- **I'll drive** — exits; you work the task list manually.
- **Modify** — describe a change, plan is regenerated.
- **Cancel** — the provisional tasks created during planning are deleted.

`/drive` picks up an approved task chain and executes it end-to-end. It marks each task `in_progress` *before* starting work and `completed` *immediately after* — never batched. While driving, it stays silent: the task list itself is the progress feed. It surfaces only for:

- **Blockers** — a tool failed in a way it can't recover from.
- **Executive decisions** — a real fork in approach not covered by the task description; a scope change.
- **Risky/destructive actions** — anything that would delete data, force-push, or modify shared state.
- **Completion** — final report.

`/drive` is standalone-invokable. If you've populated a task list any other way (manually, via `/pickup`, via another planning workflow), you can just run `/drive` and it picks up the chain.

The driving contract lives entirely inside the `/drive` skill — it does **not** depend on any rule in your global or project `CLAUDE.md`. Installs of sessionkit get the autonomous-execution semantics out of the box.

## How Skillit Works

At the end of a session, `/skillit` reviews the conversation for:

- Repeated instructions or corrections you gave Claude
- Multi-step workflows executed in a fixed pattern
- Heuristics applied consistently

It scans your existing skill library for overlap before proposing anything new, then offers to create a new skill or extend an existing one — with your approval before writing anything.

## How Suggest Permissions Works

`/suggest-permissions` reads recent session `.jsonl` files from `~/.claude/projects/` and identifies Bash commands, file edit paths, and MCP tools you approved multiple times. It proposes a `permissions.allow` block for `.claude/settings.json` with a one-line rationale for each entry, and only writes changes after you approve.

## Pairing with Other Plugins

Sessionkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Sessionkit works alongside every other plugin in the suite:

**With [swarmkit](../swarmkit)**
- Use `/skillit` after a swarm run to capture reusable patterns that emerged
- Use `/handoff` before context runs out mid-swarm to preserve state for the next agent

**With [speckit](../speckit)**
- Use `/speckit:interview` as a planning warm-up before `/spec` — arrive with clearer requirements
- `/handoff` is useful if a `/spec` session runs long and needs to continue in a new context

**With [flowkit](../flowkit)**
- Use `/handoff` before a long `/release` or `/cut` session if context is running low
- `/skillit` after a release helps capture any new conventions or one-off scripts worth keeping
