---
name: project
description: Manage a Projects/ second brain in any Obsidian vault. Handles loading project context, initializing new projects, and updating project files.
triggers:
  - "work on [project]"
  - "let's work on [project]"
  - "start project"
  - "create project"
  - "new project"
  - "update project"
  - "save notes for"
  - "what's the status of"
---

# Obsidian Project Skill

## Overview

This skill manages a `Projects/` second brain in any Obsidian vault. It handles three operations: **loading** project context at the start of a session, **initializing** new projects from template, and **updating** project files after work.

Always invoke the `vaultkit:obsidian` skill first — this skill depends on its vault connection details and command reference.

---

## Vault Parameter

All operations require a **vault name**. The caller must supply it explicitly.

If none is given, run:

```bash
obsidian vaults
```

Present the list to the user and ask them to specify which vault to use before continuing.

To resolve the vault's filesystem path (needed for `mkdir` and direct file edits):
```bash
obsidian vault="<VAULT>" vault  # prints the vault root path
```

Store the result as `$VAULT_PATH` for use in file system commands.

---

## Folder Creation Caveat

The Obsidian CLI `move` command does **not** auto-create missing destination directories. Before moving files into a new folder, always create it first:

```bash
mkdir -p "$VAULT_PATH/Projects/ProjectName"
```

Then proceed with `obsidian vault="<VAULT>" move ...` commands.

---

## Operation 1: Load Project Context

When the user wants to work on an existing project, restore full context before doing anything else.

### Steps

1. Check if the project folder exists:
   ```bash
   obsidian vault="<VAULT>" files folder="Projects/ProjectName"
   ```

2. Read all files in the project folder (Overview.md first; siblings in parallel):
   ```bash
   obsidian vault="<VAULT>" read path="Projects/ProjectName/Overview.md"
   obsidian vault="<VAULT>" read path="Projects/ProjectName/Tasks.md"       # if exists
   obsidian vault="<VAULT>" read path="Projects/ProjectName/Ideas.md"       # if exists
   obsidian vault="<VAULT>" read path="Projects/ProjectName/Architecture.md" # if exists
   ```

3. Summarize loaded context to the user: current status, active tasks, any blockers noted.

4. Proceed with the session work.

---

## Operation 2: Initialize a New Project

When a project folder does not exist yet, create it from the template.

### Steps

1. Resolve vault path:
   ```bash
   VAULT_PATH=$(obsidian vault="<VAULT>" vault)
   ```

2. Read the template:
   ```bash
   obsidian vault="<VAULT>" read path="Projects/_TEMPLATE_/Overview.md"
   ```

3. Create the destination folder (CLI move won't do this automatically):
   ```bash
   mkdir -p "$VAULT_PATH/Projects/ProjectName"
   ```

4. Create the project's Overview.md using the Write tool, filling in:
   - Project name in the H1 heading
   - One-sentence description (ask if unknown)
   - `started:` date set to today
   - `status: active`
   - Any known goals or context the user has provided

   Write to: `$VAULT_PATH/Projects/ProjectName/Overview.md`

5. Update the Projects Index table in `_README.md`:
   - Add a row: `| [[ProjectName/Overview\|ProjectName]] | Active | YYYY-MM-DD |`
   - Follow the `vaultkit:file-edit` sub-skill to edit the file with birth-time preservation.

6. Confirm creation and summarize what was set up.

---

## Operation 3: Update Project Files

After completing work, making decisions, or when status changes, update the relevant files.

### What to update and where

| Changed | File to update |
|---|---|
| Project phase or overall status | `Overview.md` — Status section |
| Task completed / new task added | `Overview.md` Tasks section (or `Tasks.md` if split) |
| Design decision made | `Overview.md` Architecture section (or `Architecture.md` if split) |
| New idea or future direction | `Overview.md` Ideas section (or `Ideas.md` if split) |
| Blocker resolved or added | `Overview.md` — Status > Blockers |

### When to split files

Split a section into its own file when it grows beyond ~30 lines or becomes hard to navigate:
- Tasks → `Tasks.md`
- Ideas → `Ideas.md`
- Architecture → `Architecture.md`

After splitting, remove the section from `Overview.md` and add a link: `See [[Tasks]]`

### Update process

1. Resolve vault path:
   ```bash
   VAULT_PATH=$(obsidian vault="<VAULT>" vault)
   ```

2. Read the file to be updated (required before Edit)

3. Follow the `vaultkit:file-edit` sub-skill to edit the file with birth-time preservation.

4. Also update `Last updated:` in `Overview.md` if you edited any project file.

**For new project files** (created with the Write tool), follow the `vaultkit:file-edit` sub-skill's new-file guidance to stamp the birth time.

---

## File Format Reference

### Overview.md frontmatter
```yaml
---
tags: [project]
status: active | on-hold | done
started: YYYY-MM-DD
---
```

### Status values
- `active` — currently being worked on
- `on-hold` — paused, not abandoned
- `done` — completed

---

## Triggers

Invoke this skill when the user says any of:
- "work on [project]" / "let's work on [project]"
- "start project [X]" / "create project [X]" / "new project [X]"
- "update project [X]" / "save notes for [project]"
- "what's the status of [project]"
- Any task where a named project has a folder in `Projects/`

---

## Notes

- Always load context before starting work — never assume you remember the project state
- Keep updates concise; these are notes for recall, not documentation
- The `_README.md` Projects Index is the master list — keep it current
- Project folder names should match what the user calls the project (no slugifying needed)
- If unsure about project name casing/spelling, check folders: `obsidian vault="<VAULT>" folders`
