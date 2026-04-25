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

Every kit under `plugins/*` that ships a manifest at `.claude-plugin/plugin.json` participates in version bumps. The root [README `#available-plugins`](../../../README.md#available-plugins) is the canonical plugin catalog — keep this table in sync when adding or removing kits.

| Plugin | plugin.json |
|--------|-------------|
| flowkit | `plugins/flowkit/.claude-plugin/plugin.json` |
| polishkit | `plugins/polishkit/.claude-plugin/plugin.json` |
| sessionkit | `plugins/sessionkit/.claude-plugin/plugin.json` |
| speckit | `plugins/speckit/.claude-plugin/plugin.json` |
| swarmkit | `plugins/swarmkit/.claude-plugin/plugin.json` |
| vaultkit | `plugins/vaultkit/.claude-plugin/plugin.json` |

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

### Step 2 — Recommend and confirm bump types

Display a table of plugins with changes:

```
Plugin      Current   Commits since last tag
----------  --------  ----------------------
swarmkit    1.0.0     4
flowkit     1.0.0     2
```

If `$ARGUMENTS` is provided (e.g. `patch` or `minor`), apply that bump type to all changed plugins and skip the rest of Step 2 — do not prompt.

Otherwise, for each changed plugin, list its commits since the last tag and derive a recommended bump from the conventional-commit prefixes:

```bash
git log {tag}..HEAD --oneline -- plugins/{name}/
```

Map prefixes to bump types (take the highest bump when multiple coexist; `major > minor > patch`):

| Commit signal | Recommended bump |
|---------------|------------------|
| `feat:` or new skill file added | **minor** |
| `fix:` / `docs:` / `chore:` / `refactor:` (no behavior change) | **patch** |
| `refactor:` with noted behavior change, or `BREAKING CHANGE:` footer anywhere | **major** |

Present the choice via the `AskUserQuestion` tool — **one question per changed plugin** — with the recommendation as the first (default) option. Each question should include a one-line rationale (e.g. "recommending **minor** — adds a new skill in `feat(flowkit): …`").

Options for each question (in this order; default first):

- **{recommendation}** — the derived bump
- The other two bump types as alternatives
- **skip** — do not bump this plugin in this run

Semver semantics for reference when explaining options:

- **patch** — bug fixes, no new behavior (`1.0.0 → 1.0.1`)
- **minor** — new skills or backward-compatible features (`1.0.0 → 1.1.0`)
- **major** — breaking changes (`1.0.0 → 2.0.0`)

Fall through to free-form prompting (asking the user to type patch/minor/major inline) only if `AskUserQuestion` is unavailable.

Skip plugins with 0 commits since their last tag unless explicitly included via `$ARGUMENTS`.

### Step 3 — Update plugin.json files

For each plugin being bumped, read the current `plugin.json`, increment the version field, and write it back.

### Step 4 — Commit plugin.json changes

Stage and commit all updated `plugin.json` files to the current branch, then push:

```bash
git add plugins/*/.claude-plugin/plugin.json
git commit -m "chore(plugins): bump <list of plugin@version>"
git push origin HEAD
```

Use a single commit message listing all bumped plugins, e.g.:
`chore(plugins): bump swarmkit@2.0.0, flowkit@1.3.0`

### Step 5 — Create git tags

After the commit is pushed, create a tag for each bumped plugin pointing at that commit:

```bash
git tag {plugin-name}--v{new-version}
```

Do NOT push tags — leave that to the release flow.

### Step 6 — Report

Print a summary of what changed:

```
Bumped:
  swarmkit  1.0.0 → 2.0.0  (tag: swarmkit--v2.0.0)
  flowkit   1.0.0 → 1.1.0  (tag: flowkit--v1.1.0)

Tags created locally. Push with:
  git push origin --tags
```

## Notes

- Always read `plugin.json` before editing it (required by Edit tool).
- Increment only the relevant semver component; reset lower components to 0 (e.g. minor bump `1.2.3 → 1.3.0`).
- If a plugin has no per-plugin tag yet, its first tag will be created from the current `plugin.json` version (no bump required unless changes exist).
