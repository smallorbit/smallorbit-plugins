# vaultkit

Obsidian vault skills for Claude Code. Read, search, edit notes, manage projects, capture decisions, and archive conversations — all via the Obsidian CLI.

## Skills

### User-facing
| Skill | Description |
|-------|-------------|
| `vaultkit:obsidian` | Interface with Obsidian vaults via the CLI |
| `vaultkit:jot` | Quickly capture a decision, task, or note into the active project |
| `vaultkit:archive-export` | Archive the latest /export output into the active Obsidian project |
| `vaultkit:project` | Manage Obsidian projects — create, load, and update project notes |

### Sub-skills (internal)
| Skill | Description |
|-------|-------------|
| `vaultkit:load-project` | Load a named Obsidian project into context |
| `vaultkit:list-projects` | List all projects in the vault's Projects folder |
| `vaultkit:file-edit` | Edit a vault file while preserving its filesystem birth time |

## Requirements

Obsidian must be open and the Obsidian CLI must be installed for vault operations to work.

## Install

Add to your Claude Code plugin list:
```
smallorbit/smallorbit-plugins/plugins/vaultkit
```
