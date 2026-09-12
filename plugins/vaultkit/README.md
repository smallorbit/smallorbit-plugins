# Vaultkit

Obsidian vault skills for Claude Code. Read, search, edit notes, manage projects, capture decisions, and archive conversations — all via the Obsidian CLI.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — vaultkit lives outside the dev loop as a utility for capturing decisions and archives alongside any work.

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
- macOS — the skills shell out to BSD `stat -f` and `SetFile` for birth-time handling, and the CLI binary ships inside the desktop app bundle at `/Applications/Obsidian.app/Contents/MacOS/obsidian`
- Xcode Command Line Tools installed (provides `SetFile`, used to stamp birth time on newly created vault files)
- [Obsidian](https://obsidian.md/) desktop app running (the CLI requires an open Obsidian instance)
- Obsidian CLI available on your `PATH` (`obsidian vaults` should list your vault)

## Skills

### User-Facing

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **obsidian** | `/obsidian` | Interface with Obsidian vaults via the CLI — read, search, tag, edit notes, manage templates, and vault maintenance. |
| **jot** | `/jot` | Quickly capture a decision, task, or note into the active project. Thin entry point over the `project` skill's update operation. |
| **archive-export** | `/archive-export` | File the latest `/export session` output into the active Obsidian project's `Conversations/` folder. |
| **project** | `/project` | Manage a `Projects/` second brain: load context, initialize new projects from template, and update project files. |
| **load-project** | `/load-project` | Load a named Obsidian project into context; lists and recommends one if no name is supplied. |

### Sub-Skills (internal)

These are called by the skills above — you don't invoke them directly. The `vaultkit:` prefix reflects how sibling skills reference them.

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **list-projects** | `vaultkit:list-projects` | List all projects in the vault's `Projects/` folder, sorted by status, with a count summary. |
| **file-edit** | `vaultkit:file-edit` | Edit a vault file in place so filesystem birth time — the source of Obsidian's `created` metadata — is preserved. |

## Typical Workflows

### Capture a decision mid-session

```
/jot decided to use CalVer for release tagging; rationale in plugin-release.md
```

The active project is inferred from conversation context (or you'll be prompted to pick one), and the note is written into the relevant section of the project's notes — Status, Tasks, Architecture, or Ideas — without disturbing the file's `created` timestamp. `Last updated:` in `Overview.md` is refreshed at the same time.

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

## How Obsidian Works

`/obsidian` is the base layer every other vaultkit skill builds on. It governs vault access via the Obsidian CLI binary — Obsidian must be running for any command to succeed. Operations require an explicit vault name; if one isn't supplied, the skill runs `obsidian vaults` and prompts. The plugin ships no permission allowlist, so every `obsidian` call prompts for approval by default. To make read-only work prompt-free, allowlist the read verbs yourself in `~/.claude/settings.json` or the project's `.claude/settings.json` — the verb list is in [`skills/obsidian/SKILL.md`](skills/obsidian/SKILL.md) under `## Permissions`. Leave the mutating verbs (`append`, `prepend`, `create`, `delete`, `rename`, `move`, `property:set`) to prompt.

## How Project Works

`/project` manages a `Projects/` second brain in an Obsidian vault laid out as described below. It handles three operations: **loading** project context at the start of a session, **initializing** new projects from template, and **updating** project files after work. `/jot` is the lightweight entry point for updates, and `/load-project` for loading and discovery — it calls `vaultkit:list-projects` internally when no project name is given. The skill always invokes `vaultkit:obsidian` first to resolve vault connection details, and routes file mutations through `vaultkit:file-edit` to preserve filesystem birth time — the source of Obsidian's `created` metadata.

### Vault layout

The skills assume the vault already contains:

- `Projects/_TEMPLATE_/Overview.md` — the template new projects are initialized from.
- `_README.md` with a Projects Index table; initialization adds a row of the form `| [[ProjectName/Overview\|ProjectName]] | Active | YYYY-MM-DD |`.
- `Projects/<Name>/Overview.md` per project, with frontmatter `tags: [project]`, `status: active | on-hold | done`, `started: YYYY-MM-DD` — `list-projects` reads `status` from there.
- Optionally `Tasks.md`, `Ideas.md`, and `Architecture.md` alongside `Overview.md`, once those sections outgrow it.

## How Archive Export Works

`/archive-export` picks up the latest `/export session` output from the current working directory and files it into the active project's `Conversations/` folder. `/export session` writes `./session.txt` in the cwd, and that is where `archive-export` looks first — if it isn't there, the skill can search subdirectories for a misplaced `session.txt` before falling back to asking you to re-run the export. The active project is inferred from conversation context; when that's unclear, the skill currently lists projects from a vault hardcoded as `Personal` to ask which one to file under.

Two copies are created:

- **`.txt`** — plain text, formatted for native viewing.
- **`.md`** — Obsidian-renderable, searchable, embedding the `.txt` as an attachment and recording the session ID so the conversation can be resumed later.

Once both copies are written, the source `./session.txt` is deleted from the working directory.

Both new files get their birth time stamped per `vaultkit:file-edit`'s new-file guidance — important because Obsidian surfaces the `created` field in dataview queries, sort orders, and plugin behaviors.

## Pairing with Other Plugins

Vaultkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Vaultkit captures what happens during and after a session into a durable Obsidian second brain.

**With [sessionkit](../sessionkit)**

- Run `/handoff` to capture a session's state to `.sessionkit/HANDOFF.md`, then `/archive-export` to file the conversation export into the active project — the handoff lives on disk next to the code, the archive lives in Obsidian for long-term recall.
- Use `/pickup` in the next session to restore context, then `/jot` to record what you decide as you go.
