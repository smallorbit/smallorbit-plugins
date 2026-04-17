# vaultkit — Source Skill Audit

Audit of 7 source skills from `~/src/claude-config/skills/`. Documents current names, descriptions, triggers, cross-skill references, required renames, and namespace updates needed before migration.

---

## Skills

### 1. `obsidian`

**Source path:** `obsidian/SKILL.md`
**Description:** Interface with Obsidian vaults via the Obsidian CLI. Use for reading, searching, tagging, editing notes, managing templates, and vault maintenance tasks.
**Triggers:** Not declared via frontmatter — invoked directly by name or by other skills.
**Cross-skill references:** None (this is the root skill; others depend on it).
**Rename needed:** No — `obsidian` is a clear, non-prefixed name and suitable as-is.
**Namespace updates needed:** None (no outgoing skill calls).

---

### 2. `obsidian-project`

**Source path:** `obsidian-project/SKILL.md`
**Description:** (No frontmatter description) Manages a `Projects/` second brain in any Obsidian vault. Handles loading project context, initializing new projects, and updating project files.
**Triggers (frontmatter):**
- "work on [project]"
- "let's work on [project]"
- "start project"
- "create project"
- "new project"
- "update project"
- "save notes for"
- "what's the status of"

**Cross-skill references:**
- Calls `obsidian` (declared as a prerequisite: "Always invoke the `obsidian` skill first")
- Calls `obsidian-file-edit` sub-skill (Operation 3, Update step)

**Rename needed:** Yes — drop prefix. Target name: `project`
**Namespace updates needed:**
- Any caller referencing `obsidian-project` must be updated to `project`
- Internal reference to `obsidian-file-edit` must be updated to `file-edit`

---

### 3. `obsidian-load-project`

**Source path:** `obsidian-load-project/SKILL.md`
**Description:** Load an Obsidian project into context. If no project name is given, lists projects and recommends one based on current conversation context.
**Triggers (frontmatter):**
- "load project"
- "load [project]"
- "open project"

**Cross-skill references:**
- Calls `obsidian` ("Always invoke the `obsidian` skill first")
- Calls `obsidian-project` (Operation 1: Load Project Context)
- Calls `obsidian-list-projects` (when no project name provided)

**Rename needed:** Yes — drop prefix. Target name: `load-project`
**Namespace updates needed:**
- Reference to `obsidian-project` → `project`
- Reference to `obsidian-list-projects` → `list-projects`

---

### 4. `obsidian-list-projects`

**Source path:** `obsidian-list-projects/SKILL.md`
**Description:** List all projects in an Obsidian vault's Projects folder, with status and count summary. Sub-skill used by obsidian-load-project.
**Triggers:** None declared — invoked by `obsidian-load-project`.
**Cross-skill references:**
- Calls `obsidian` ("Always invoke the `obsidian` skill first")

**Rename needed:** Yes — drop prefix. Target name: `list-projects`
**Namespace updates needed:**
- Description still references `obsidian-load-project` — update to `load-project`

---

### 5. `obsidian-file-edit`

**Source path:** `obsidian-file-edit/SKILL.md`
**Description:** Edit an Obsidian vault file while preserving its filesystem birth time. Use whenever editing an existing vault file via the Edit tool.
**Triggers:** None declared — invoked as a sub-skill.
**Cross-skill references:** None (leaf skill).
**Rename needed:** Yes — drop prefix. Target name: `file-edit`
**Namespace updates needed:** None (no outgoing skill calls). All callers (`obsidian-project`, `jot`, `archive-export`) must update their references from `obsidian-file-edit` to `file-edit`.

---

### 6. `jot`

**Source path:** `jot/SKILL.md`
**Description:** Quickly capture a decision, task, or note into the active Obsidian project. Thin entry point for obsidian-project's update operation.
**Triggers (frontmatter):**
- "jot this down"
- "update my notes"
- "record this decision"
- "save progress"
- "update the project notes"

**Cross-skill references:**
- Calls `obsidian-project` (Operation 3: Update Project Files)
- Implicitly depends on `obsidian-file-edit` via `obsidian-project`

**Rename needed:** No — `jot` is already a clean name.
**Namespace updates needed:**
- Reference to `obsidian-project` → `project`

---

### 7. `archive-export`

**Source path:** `archive-export/SKILL.md`
**Description:** Archive the latest /export output into the active Obsidian project's Conversations folder. Use after the user runs /export session from the workspace root.
**Triggers (frontmatter):**
- "archive the export"
- "save the conversation"
- "file the export"
- "archive this conversation"

**Cross-skill references:**
- Calls `get-session-id` sub-skill (from sessionkit — external dependency)
- References `obsidian-file-edit` in comments (birth time pattern for new files)

**Rename needed:** No — `archive-export` is already a clean name.
**Namespace updates needed:**
- Comment reference to `obsidian-file-edit` → `file-edit`
- `get-session-id` is from sessionkit — must remain a cross-plugin reference or be documented as an external dependency

---

## Rename Summary

| Current name | Target name | Type |
|---|---|---|
| `obsidian` | `obsidian` | no change |
| `obsidian-project` | `project` | rename |
| `obsidian-load-project` | `load-project` | rename |
| `obsidian-list-projects` | `list-projects` | rename |
| `obsidian-file-edit` | `file-edit` | rename |
| `jot` | `jot` | no change |
| `archive-export` | `archive-export` | no change |

---

## Cross-skill Call Graph (post-rename)

```
obsidian            (root — no outgoing calls)
project             → obsidian, file-edit
load-project        → obsidian, project, list-projects
list-projects       → obsidian
file-edit           (leaf — no outgoing calls)
jot                 → project (→ file-edit transitively)
archive-export      → get-session-id (sessionkit — external)
```

---

## External Dependencies

- `get-session-id` (sessionkit) — called by `archive-export`. This is a cross-plugin dependency. Options:
  1. Document it as a required companion plugin (sessionkit must be installed)
  2. Inline the session ID resolution logic into `archive-export`
  3. Make it optional with a fallback (manual session ID entry)
