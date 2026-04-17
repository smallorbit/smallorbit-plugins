---
name: load-project
description: Load an Obsidian project into context. If no project name is given, lists projects and recommends one based on current conversation context.
triggers:
  - "load project"
  - "load [project]"
  - "open project"
---

# vaultkit:load-project

Loads a named Obsidian project into context using the `vaultkit:project` skill. If no project name is supplied, lists available projects and recommends the most contextually relevant one.

Always invoke the `vaultkit:obsidian` skill first — this skill depends on its vault connection details and command reference.

## Steps

### If a project name is provided

1. Use the `vaultkit:project` skill (Operation 1: Load Project Context) to load the named project, passing through the vault parameter.

### If no project name is provided

1. Based on the current conversation context (recent topics, files mentioned, tasks discussed), identify the project that most likely applies.
2. Invoke the `vaultkit:list-projects` skill, passing the vault parameter and the inferred project name as `recommended`.
3. Ask the user which project to load:
   > "Which project should I load? (I'm guessing **Project Name** based on our current context.)"
4. Once the user confirms or selects a different project, use the `vaultkit:project` skill (Operation 1: Load Project Context) to load it, passing through the vault parameter.
