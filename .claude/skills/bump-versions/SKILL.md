---
name: bump-versions
description: Bump plugin.json versions for changed plugins and create per-plugin semver git tags. Run before every release.
triggers:
  - "bump versions"
  - "bump plugin versions"
  - "version bump"
---

# Bump Plugin Versions

Bumps `plugin.json` version fields for plugins that have changed since their last release, then creates per-plugin git tags so clients detect the update.

## Plugin locations

| Plugin | plugin.json |
|--------|-------------|
| swarmkit | `plugins/swarmkit/.claude-plugin/plugin.json` |
| flowkit | `plugins/flowkit/.claude-plugin/plugin.json` |
| sessionkit | `plugins/sessionkit/.claude-plugin/plugin.json` |
| speckit | `plugins/speckit/.claude-plugin/plugin.json` |

## Git tag format

Per-plugin tags use the format `{plugin-name}--v{version}` (e.g. `swarmkit--v1.2.0`).  
Repo-level calver tags (`v2026.4.16`) are separate and not used for plugin version detection.

## Process

### Step 1 — Detect changed plugins

For each plugin, find the most recent `{plugin-name}--v*` tag:

```bash
git tag --list 'swarmkit--v*' | sort -V | tail -1
```

If no per-plugin tag exists, use the current version in `plugin.json` as the baseline and treat all files as changed.

Count commits touching the plugin's directory since that tag:

```bash
git log {tag}..HEAD --oneline -- plugins/{name}/ | wc -l
```

### Step 2 — Present summary and ask for bump types

Display a table of plugins with changes:

```
Plugin      Current   Commits since last tag
----------  --------  ----------------------
swarmkit    1.0.0     4
flowkit     1.0.0     2
```

For each changed plugin, ask the user whether to bump **patch**, **minor**, or **major**:

- **patch** — bug fixes, no new behavior (`1.0.0 → 1.0.1`)
- **minor** — new skills or backward-compatible features (`1.0.0 → 1.1.0`)
- **major** — breaking changes (`1.0.0 → 2.0.0`)

If `$ARGUMENTS` is provided (e.g. `patch` or `minor`), apply that bump type to all changed plugins without asking.

Skip plugins with 0 commits since their last tag unless explicitly included via `$ARGUMENTS`.

### Step 3 — Update plugin.json files

For each plugin being bumped, read the current `plugin.json`, increment the version field, and write it back.

### Step 4 — Create git tags

After updating all `plugin.json` files, create a tag for each bumped plugin:

```bash
git tag {plugin-name}--v{new-version}
```

Do NOT push tags — leave that to the release flow.

### Step 5 — Report

Print a summary of what changed:

```
Bumped:
  swarmkit  1.0.0 → 1.0.1  (tag: swarmkit--v1.0.1)
  flowkit   1.0.0 → 1.1.0  (tag: flowkit--v1.1.0)

Next: commit the plugin.json changes, then push tags with:
  git push origin --tags
```

## Notes

- Always read `plugin.json` before editing it (required by Edit tool).
- Increment only the relevant semver component; reset lower components to 0 (e.g. minor bump `1.2.3 → 1.3.0`).
- If a plugin has no per-plugin tag yet, its first tag will be created from the current `plugin.json` version (no bump required unless changes exist).
