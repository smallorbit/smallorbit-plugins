---
name: jot
description: Quickly capture a decision, task, or note into the active Obsidian project. Thin entry point for vaultkit:project's update operation.
triggers:
  - "jot this down"
  - "update my notes"
  - "record this decision"
  - "save progress"
  - "update the project notes"
---

# Jot

Quick capture for the active Obsidian project. Delegates to the `vaultkit:project` skill — Operation 3 (Update Project Files).

If `$ARGUMENTS` is provided, treat it as the specific note, decision, or task to record.

## Process

Invoke the `vaultkit:project` skill, Operation 3: **Update Project Files**.

That operation handles:
- Identifying the active project (from conversation context or by prompting)
- Reading the relevant file before editing
- Writing the edit in place to preserve birth time (via `vaultkit:file-edit`)
- Determining what changed: decisions, tasks, status, blockers
- Keeping entries concise — recall notes, not documentation
