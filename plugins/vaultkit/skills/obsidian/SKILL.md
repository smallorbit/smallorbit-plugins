---
name: obsidian
description: Interface with Obsidian vaults via the Obsidian CLI. Use for reading, searching, tagging, editing notes, managing templates, and vault maintenance tasks.
---

# Obsidian Vault Skill

## Overview

This skill governs how to interact with Obsidian vaults on behalf of the user. All vault access is via the Obsidian CLI binary. Obsidian must be open for CLI commands to work.

## Vault Parameter

All operations require a **vault name**. The caller must supply it explicitly.

If none is given, run:

```bash
obsidian vaults
```

Present the list to the user and ask them to specify which vault to use before continuing.

**If a vault command returns "Vault not found":** run `obsidian vaults`, present the list to the user, confirm the correct name, and flag any stale caller reference (e.g., memory files, hardcoded vault names in sub-skills) before retrying. Do not silently retry with a guess.

## Connection

- **CLI binary**: `/Applications/Obsidian.app/Contents/MacOS/obsidian`
- **CLI invocation**: `obsidian vault=<VAULT> <command> [options]`

To resolve the vault's filesystem path (needed for `stat`, `SetFile`, `mkdir`):
```bash
obsidian vault=<VAULT> vault  # prints the vault root path
```

Store the result as `$VAULT` for use in filesystem commands. Obsidian must be running for CLI commands to work.

## Permissions

Read-only `obsidian vault=<VAULT>` commands are pre-approved in global settings (`~/.claude/settings.json`) and will not prompt the user. These include:

```
tags, tag, search, search:context, files, folders, file, folder,
read, properties, property:read, backlinks, links, outline,
vault, recents, wordcount, aliases, orphans, deadends, unresolved,
template, templates, plugin, plugins, plugins:enabled
```

`Edit($VAULT/*)` is approved at the workspace level (`claude-workspace/.claude/settings.json`).

Write operations via the CLI (`append`, `prepend`, `create`, `delete`, `rename`, `move`, `property:set`) will prompt the user unless explicitly pre-approved.

## Command Reference

### Reading & Discovery
```bash
obsidian vault=<VAULT> read path="<path>"           # Read file contents
obsidian vault=<VAULT> search query="<text>"        # Full-text search
obsidian vault=<VAULT> search:context query="<text>" # Search with surrounding context
obsidian vault=<VAULT> files folder="<path>"        # List files (optionally filtered)
obsidian vault=<VAULT> folders                      # List all folders
obsidian vault=<VAULT> recents                      # Recently opened files
obsidian vault=<VAULT> file "<name>"                # File info (path, size, dates)
obsidian vault=<VAULT> outline path="<path>"        # Headings outline
obsidian vault=<VAULT> wordcount path="<path>"      # Word/character count
```

### Tags
```bash
obsidian vault=<VAULT> tags counts format=json      # All tags with occurrence counts
obsidian vault=<VAULT> tag name="<tag>" verbose     # Files containing a specific tag
```

### Properties / Frontmatter
```bash
obsidian vault=<VAULT> properties file="<name>"     # All properties on a file
obsidian vault=<VAULT> property:read name="<prop>" path="<path>"  # Read one property
obsidian vault=<VAULT> property:set name="<prop>" value="<val>" path="<path>"  # Set a property
```

### Graph / Links
```bash
obsidian vault=<VAULT> backlinks file="<name>"      # What links to this file
obsidian vault=<VAULT> links path="<path>"          # Outgoing links from file
obsidian vault=<VAULT> orphans                      # Files with no incoming links
obsidian vault=<VAULT> deadends                     # Files with no outgoing links
obsidian vault=<VAULT> unresolved                   # Unresolved wikilinks
```

### Templates
```bash
obsidian vault=<VAULT> templates                    # List all templates
obsidian vault=<VAULT> template:read name="<name>"  # Read a template's content
```

### Daily Notes
```bash
obsidian vault=<VAULT> daily:read                   # Read today's daily note
obsidian vault=<VAULT> daily:path                   # Get path of today's daily note
obsidian vault=<VAULT> daily:append content="<text>" # Append to today's daily note
```

### Writing (requires approval)
```bash
obsidian vault=<VAULT> append path="<path>" content="<text>"   # Append to file
obsidian vault=<VAULT> prepend path="<path>" content="<text>"  # Prepend to file
obsidian vault=<VAULT> create name="<name>" content="<text>"   # Create new file
obsidian vault=<VAULT> rename path="<path>" name="<new>"       # Rename file
obsidian vault=<VAULT> move path="<path>" to="<dest>"          # Move file
obsidian vault=<VAULT> delete path="<path>"                    # Delete (moves to trash)
```

### Plugins
```bash
obsidian vault=<VAULT> plugins:enabled              # List enabled plugins
obsidian vault=<VAULT> plugins filter=community     # List community plugins
obsidian vault=<VAULT> plugin id=<id>               # Plugin details
obsidian vault=<VAULT> plugin:install id=<id> enable # Install + enable a plugin
```

## Edit Strategy

Choose the right approach based on the type of change:

### 1. Frontmatter-only changes → use CLI `property:set`
Preserves all file metadata. Preferred when only updating YAML properties.
```bash
obsidian vault=<VAULT> property:set name="status" value="done" path="Notes/my-note.md"
```

### 2. Append/prepend operations → use CLI `append` or `prepend`
Preserves all file metadata. Use when adding content to start or end of a file.
```bash
obsidian vault=<VAULT> daily:append content="- Follow up with Adam"
```

### 3. In-body content edits (find & replace, tag renames, etc.) → use Edit tool + restore birth time
The Edit tool writes via a temp file + rename on macOS, which **resets the filesystem birth time**. Capture the birth time **before** editing, then restore it exactly afterward.

**For existing files:**
```bash
# Step 1: Capture birth time before editing
BIRTH=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "$VAULT/<path>")

# Step 2: Make the edit (Edit tool)

# Step 3: Restore exact birth time
SetFile -d "$BIRTH" "$VAULT/<path>"
```

**For new files just created (Write tool):**
```bash
SetFile -d "$(date '+%m/%d/%Y %H:%M:%S')" "$VAULT/<path>"
```

**Always verify after restoring:**
```bash
stat -f "Birth: %SB | %N" "$VAULT/<path>"
```

### Known Limitation
There is no CLI command for in-body text replacement (no `replace` or `patch` command). The Obsidian CLI only supports `append` and `prepend` for writing to existing file bodies. Any find-and-replace operation requires direct file editing and subsequent birth time restoration.

## Tag Conventions

The user's vault uses a **verb/noun** tag hierarchy for action-oriented tags:

- **Correct**: `#ask/personname` (e.g., `#ask/adam`, `#ask/shawna`)
- **Incorrect**: `#personname/ask` (old format — always migrate to verb/noun)

When scanning for or creating action tags, enforce verb/noun order. Other known action tag patterns to follow the same convention if encountered:
- `#ask/<person>` — need to ask this person something
- `#todo/<context>` — to-do item in a given context

## Workflow: Tag Standardization

When asked to standardize tags:

1. `obsidian vault=<VAULT> tags counts format=json` — get full tag list
2. Identify non-standard patterns (e.g., `#name/ask`)
3. `obsidian vault=<VAULT> tag name="<tag>" verbose` — get exact file list per tag (do NOT use `search` — it matches broadly)
4. Read each file via `Read` tool (required before Edit)
5. Before editing each file, capture its birth time: `BIRTH=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "<path>")`
6. Edit files with Edit tool
7. Restore exact birth time with `SetFile -d "$BIRTH" "<path>"` for each edited file

## Workflow: Vault Health Check

Useful commands for periodic vault maintenance:
```bash
obsidian vault=<VAULT> orphans          # Notes no one links to
obsidian vault=<VAULT> deadends         # Notes that link nowhere
obsidian vault=<VAULT> unresolved       # Broken wikilinks
obsidian vault=<VAULT> tags counts sort=count format=json  # Tag usage audit
```

## Notes

- The `search` command does broad text matching and will return false positives for tag queries — always use `obsidian vault=<VAULT> tag name="<tag>" verbose` to get precise per-tag file lists
- File paths in CLI commands are relative to the vault root (`$VAULT`)
- The `file` command resolves by name (like wikilinks); `path` is exact — prefer `path=` when you know the exact location
- Quote values with spaces: `name="My Note"`, `path="Folder/Subfolder/2024-01-01 - Note.md"`
