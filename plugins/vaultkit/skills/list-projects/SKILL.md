---
name: list-projects
description: List all projects in an Obsidian vault's Projects folder, with status and count summary. Sub-skill used by obsidian-load-project.
---

# obsidian-list-projects

Lists all projects in an Obsidian vault's `Projects/` folder, sorted by status, with a count summary.

Always invoke the `obsidian` skill first — this skill depends on its vault connection details and command reference.

## Vault Parameter

All operations require a **vault name**. The caller must supply it explicitly.

If none is given, run:
```bash
obsidian vaults
```
Present the list to the user and ask them to specify which vault to use before continuing.

## Steps

1. List all project folders:
   ```bash
   obsidian vault="<VAULT>" files folder="Projects"
   ```

2. Read the `status` field from each project's `Overview.md` in parallel — issue all calls simultaneously, one per project:
   ```bash
   obsidian vault="<VAULT>" property:read name="status" path="Projects/<ProjectName>/Overview.md"
   ```

3. Display as a formatted table, sorted by status (active first, then on-hold, then done). If a `recommended` project name was passed by the caller, bold that row and append `← recommended`:

   | Project | Status |
   |---------|--------|
   | **Project Name** | active | ← recommended |
   | Other Project | on-hold |

4. After the table, show a count summary: e.g. `5 active · 2 on-hold · 1 done`
