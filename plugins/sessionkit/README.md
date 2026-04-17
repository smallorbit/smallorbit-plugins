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
| **handoff** | `/handoff` | Captures session goal, progress, git state, and remaining work into `.claude/HANDOFF.md`. Use when context is running low or when switching agents. |
| **pickup** | `/pickup` | Loads `.claude/HANDOFF.md` at the start of a new session and orients the agent to continue seamlessly. |
| **skillit** | `/skillit` | Reflects on the current session to identify patterns worth encoding as reusable skills. Checks for existing overlap before proposing anything new. |
| **suggest-permissions** | `/suggest-permissions` | Scans recent session history for repeatedly approved permissions and proposes additions to `.claude/settings.json` to reduce future prompts. |

### Sub-Skills (internal)

| Skill | Used by | Purpose |
|-------|---------|---------|
| **get-session-id** | suggest-permissions | Resolves the current Claude Code session UUID from `~/.claude/projects/`. |

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

`/handoff` collects git state, todo files, and conversation history, synthesizes them into a structured document, and writes it to `.claude/HANDOFF.md` only after you approve the draft.

`/pickup` reads that document at the start of a fresh session and produces an orientation summary — goal, progress, git state, remaining work, and key context — without re-executing anything.

The two skills are intentionally separate: handoff writes, pickup reads. The handoff file is never modified or deleted by pickup.

## Handoff Document Structure

`.claude/HANDOFF.md` is a structured Markdown file with these sections:

| Section | Contents |
|---------|----------|
| **Goal** | One or two sentences describing what this session is working toward |
| **Progress** | Bullet list of completed steps and key decisions made |
| **Git State** | Current branch, staged/unstaged files, recent commits |
| **Remaining Work** | Prioritized list of what still needs to be done |
| **Context** | Gotchas, constraints, or non-obvious state the next agent must know |

You can manually edit `.claude/HANDOFF.md` between sessions — `/pickup` reads whatever is there.

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
