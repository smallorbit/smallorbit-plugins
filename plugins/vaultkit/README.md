# Vaultkit

Obsidian vault skills for Claude Code. Read, search, edit notes, manage projects, capture decisions, and archive conversations — all via the Obsidian CLI.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install vaultkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/vaultkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [Obsidian](https://obsidian.md/) desktop app running (the CLI requires an open Obsidian instance)
- Obsidian CLI installed and authenticated against your vault (`obsidian vaults` should list your vault)

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **obsidian** | `/obsidian` | Interface with Obsidian vaults via the CLI — read, search, tag, edit notes, manage templates, and vault maintenance. |
| **jot** | `/jot` | Quickly capture a decision, task, or note into the active project. Thin entry point over the `project` skill's update operation. |
| **archive-export** | `/archive-export` | File the latest `/export session` output into the active Obsidian project's `Conversations/` folder. |
| **project** | `/project` | Manage a `Projects/` second brain: load context, initialize new projects from template, and update project files. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly. The `vaultkit:` prefix reflects how sibling skills reference them.

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **load-project** | `vaultkit:load-project` | Load a named Obsidian project into context; lists and recommends one if no name is supplied. |
| **list-projects** | `vaultkit:list-projects` | List all projects in the vault's `Projects/` folder, sorted by status, with a count summary. |
| **file-edit** | `vaultkit:file-edit` | Edit a vault file in place so filesystem birth time — the source of Obsidian's `created` metadata — is preserved. |

## Typical Workflows

### Capture a decision mid-session

```
/jot decided to use CalVer for release tagging; rationale in plugin-release.md
```

The active project is inferred from conversation context (or you'll be prompted to pick one), and the note is appended without disturbing the file's `created` timestamp.

### Archive a conversation export

```
/export session                    # writes ./session.txt in the cwd
/archive-export                    # files it into the active project's Conversations/
```

Two artifacts land in Obsidian: a `.txt` copy for plain-text viewing and a `.md` companion with the session ID embedded for resuming.

### Load a project at the start of a session

```
/load-project smallorbit-plugins   # pulls project notes, status, and context
```

If no name is provided, the skill lists available projects and recommends the most contextually relevant one.

## How Jot Works

`/jot` is a thin entry point into the `vaultkit:project` skill's update operation. It:

1. Identifies the active project from conversation context, or prompts if unclear.
2. Reads the target file before editing, then determines what changed — decisions, tasks, status, blockers.
3. Writes the edit in place via `vaultkit:file-edit` so Obsidian's `created` metadata is preserved.
4. Keeps entries concise — recall notes, not documentation.

Because it delegates to the `project` skill, `/jot` benefits from the same project-awareness and file-hygiene conventions that `/project` applies.

## How Archive Export Works

`/archive-export` picks up the latest `/export session` output from the current working directory and files it into the active project's `Conversations/` folder. The convention is strict: `/export session` always writes `./session.txt` in the cwd, and `archive-export` looks only there.

Two copies are created:

- **`.txt`** — plain text, formatted for native viewing.
- **`.md`** — Obsidian-renderable, searchable, embedding the `.txt` as an attachment and recording the session ID so the conversation can be resumed later.

Editing flows through `vaultkit:file-edit` to preserve birth time — important because Obsidian surfaces the `created` field in dataview queries, sort orders, and plugin behaviors.

## Pairing with Other Plugins

Vaultkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Vaultkit captures what happens during and after a session into a durable Obsidian second brain.

**With [sessionkit](../sessionkit)**

- Run `/handoff` to capture a session's state to `.sessionkit/HANDOFF.md`, then `/archive-export` to file the conversation export into the active project — the handoff lives on disk next to the code, the archive lives in Obsidian for long-term recall.
- Use `/pickup` in the next session to restore context, then `/jot` to record what you decide as you go.
