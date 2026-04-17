---
name: jot
description: Quickly capture a decision, task, or note into the active Obsidian project. Thin entry point for obsidian-project's update operation.
triggers:
  - "jot this down"
  - "update my notes"
  - "record this decision"
  - "save progress"
  - "update the project notes"
---

# Jot

Quick capture for the active Obsidian project. Delegates to the `obsidian-project` skill — Operation 3 (Update Project Files).

If `$ARGUMENTS` is provided, treat it as the specific note, decision, or task to record.

## Process

Invoke the `obsidian-project` skill, Operation 3: **Update Project Files**.

That operation handles:
- Identifying the active project (from conversation context or by prompting)
- Reading the relevant file before editing
- Capturing birth time, making the edit, restoring birth time (via `obsidian-file-edit`)
- Determining what changed: decisions, tasks, status, blockers
- Keeping entries concise — recall notes, not documentation
