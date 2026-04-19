---
name: detect-kits
description: Detect which sibling kits are installed at user and project scope, merge both scopes, and return a structured map of installed kits with versions and skills.
---

# Detect Kits

Sub-skill that discovers which sibling kits (speckit, swarmkit, polishkit, flowkit, sessionkit, vaultkit) are available in the current environment. Called by metakit scenario skills before rendering a plan or executing steps.

## Process

### 1. Read user-scope settings

Read `~/.claude/settings.json` using the Read tool. Extract the `plugins` array (or `enabledPlugins`, depending on the settings schema). Collect each entry whose name matches the canonical kit list:

```
speckit | swarmkit | polishkit | flowkit | sessionkit | vaultkit
```

Tag each matched entry with `"scope": "user"`.

### 2. Read project-scope settings

Identify the project root (the directory containing `.claude/` nearest to CWD). Read `<project-root>/.claude/settings.json` with the Read tool. Apply the same extraction logic as step 1 and tag matched entries with `"scope": "project"`.

### 3. Merge scopes — project wins

Build a single detection map by starting with all user-scope entries, then overlaying project-scope entries. When the same kit appears in both scopes, the project-scope entry replaces the user-scope entry entirely.

### 4. Resolve version and skills for each detected kit

For each kit in the merged map:

**If running inside the monorepo** (a `plugins/<kit-name>/` directory exists relative to CWD):

```
Read plugins/<kit-name>/.claude-plugin/plugin.json   → extract "version"
Glob plugins/<kit-name>/skills/*/SKILL.md            → collect skill names (directory name only, not path)
```

**Otherwise (installed from cache)**:

Locate the plugin cache dir. Typical path: `~/.claude/plugins/<kit-name>/`. Read `plugin.json` there for `version`, and glob `skills/*/SKILL.md` for skill names.

Populate the map entry:

```json
{
  "version": "<semver from plugin.json>",
  "scope": "user" | "project",
  "skills": ["skill-name-1", "skill-name-2", ...]
}
```

### 5. Return the detection map

Return the complete map. If no kits are detected, return an empty object `{}`.

## Output shape

```json
{
  "speckit":    { "version": "1.2.7", "scope": "user",    "skills": ["spec", "catalog", "issue", "interview"] },
  "swarmkit":   { "version": "2.4.1", "scope": "project", "skills": ["swarm", "pick-issue", "merge-stack", "self-review"] },
  "flowkit":    { "version": "2.0.0", "scope": "user",    "skills": ["pr", "commit", "release", "stage"] },
  "sessionkit": { "version": "1.1.0", "scope": "user",    "skills": ["handoff", "pickup", "skillit"] }
}
```

Only kits that are installed appear as keys. Missing kits are absent from the map, not present with null values.

## Notes

### "Is kit X installed?" helper pattern

A truthy lookup on the kit name key is sufficient:

```
if detectionMap["swarmkit"] → swarmkit is installed
if !detectionMap["polishkit"] → polishkit is not available; skip or degrade gracefully
```

### Fallback path (Plan B)

If both settings files are missing, unreadable, or yield no kit entries after parsing, run:

```bash
claude plugin list
```

Parse each line for a kit name matching the canonical list. Treat all entries from this fallback as `"scope": "user"` since scope is indeterminate. Version and skills discovery proceeds normally (step 4) for any kits found this way.

Use this fallback only when settings-file parsing is inconclusive — not as the default path, because `claude plugin list` is slower and its output format may change across CLI versions.

### Canonical kit list

```
speckit | swarmkit | polishkit | flowkit | sessionkit | vaultkit
```

Entries in settings files that do not match this list are ignored by this sub-skill.
