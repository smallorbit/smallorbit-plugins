# vaultkit

Obsidian vault skills for Claude Code. Read, search, edit notes, manage projects, capture decisions, and archive conversations — all via the Obsidian CLI.

## Skills

### User-facing

| Skill | Description |
|-------|-------------|
| `obsidian` | Core vault interface — read, search, tag, edit notes, manage templates and vault health |
| `jot` | Quickly capture a decision, task, or note into the active project |
| `archive-export` | Archive a conversation export into the active project's Conversations folder |
| `project` | Manage the Projects/ second brain — load, initialize, and update projects |

### Sub-skills

| Skill | Description |
|-------|-------------|
| `load-project` | Load a named project into context (delegates to `project`) |
| `list-projects` | List all projects with status summary |
| `file-edit` | Edit a vault file while preserving filesystem birth time |

## Skills coming soon

Skills are being migrated from `claude-config` and will land here once renamed and audited. See `AUDIT.md` for the current inventory.
