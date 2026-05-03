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
| squadkit | `plugins/squadkit/.claude-plugin/plugin.json` |
| swarmkit | `plugins/swarmkit/.claude-plugin/plugin.json` |
| vaultkit | `plugins/vaultkit/.claude-plugin/plugin.json` |

## Git tag format

Per-plugin tags use the format `{plugin-name}--v{version}` (e.g. `swarmkit--v1.2.0`).  
Repo-level calver tags (`v2026.4.16`) are separate and not used for plugin version detection.

## Process

### Step 1 — Detect changed plugins

Run the detection script once to get a JSON array of plugins with uncommitted changes since their last per-plugin tag:

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
bash "$SKILL_DIR/scripts/detect_changed.sh"
```

The script emits a bare JSON array on stdout:

```json
[
  {"plugin": "swarmkit", "last_tag": "swarmkit--v5.1.0", "commit_count": 2, "current_version": "5.1.0", "suggested_bump": "minor"},
  {"plugin": "flowkit",  "last_tag": "flowkit--v1.2.0",  "commit_count": 1, "current_version": "1.2.0", "suggested_bump": "patch"}
]
```

Only plugins with `commit_count > 0` (or no prior tag) are included. If the array is empty, no plugins have changed — report that and stop.

If `$ARGUMENTS` is provided (e.g. `patch` or `minor`), apply that bump type to all changed plugins and skip the rest of Step 2 — do not prompt.

### Step 2 — Recommend and confirm bump types

Display a table of plugins with changes (from the Step 1 JSON), using the `suggested_bump` field already computed by the script:

```
Plugin      Current   Commits since last tag   Suggested bump
----------  --------  ----------------------   --------------
swarmkit    5.1.0     2                        minor
flowkit     1.2.0     1                        patch
```

The `suggested_bump` is derived from conventional-commit prefixes across all commits in the range (`major > minor > patch`):

| Commit signal | Recommended bump |
|---------------|------------------|
| `!:` in subject or `BREAKING CHANGE` in commit body | **major** |
| `feat:` / `feat(…):` prefix | **minor** |
| Any other prefix (`fix`, `chore`, `refactor`, etc.) | **patch** |

Present the choice via the `AskUserQuestion` tool — **one question per changed plugin** — with `suggested_bump` as the first (default) option. Each question should include a one-line rationale (e.g. "recommending **minor** — adds a new skill in `feat(flowkit): …`").

Options for each question (in this order; default first):

- **{recommendation}** — the derived bump
- The other two bump types as alternatives
- **skip** — do not bump this plugin in this run

Semver semantics for reference when explaining options:

- **patch** — bug fixes, no new behavior (`1.0.0 → 1.0.1`)
- **minor** — new skills or backward-compatible features (`1.0.0 → 1.1.0`)
- **major** — breaking changes (`1.0.0 → 2.0.0`)

Fall through to free-form prompting (asking the user to type patch/minor/major inline) only if `AskUserQuestion` is unavailable.

### Step 3 — Update plugin.json files

For each plugin being bumped, read the current `plugin.json`, increment the version field, and write it back.

### Step 4 — Commit and publish plugin.json changes

Stage and commit all updated `plugin.json` files to the current branch:

```bash
BUMPED_LIST="<comma-separated list of plugin@new-version>"
git add plugins/*/.claude-plugin/plugin.json
git commit -m "chore(plugins): bump $BUMPED_LIST"
```

Use a single commit message listing all bumped plugins, e.g.:
`chore(plugins): bump swarmkit@2.0.0, flowkit@1.3.0`

Then publish the commit via the [`flowkit:push-or-pr`](../../../plugins/flowkit/skills/push-or-pr/SKILL.md) sub-skill so the bump lands on the protected branch even when direct pushes are rejected. Set `PREFIX`, `PR_TITLE`, and `PR_BODY` before inlining the snippet:

```bash
PREFIX="chore/bump-plugins"
PR_TITLE="chore(plugins): bump $BUMPED_LIST"
PR_BODY="## Summary

Bump plugin.json versions for plugins changed since their last release.

## Changes

$(printf '%s\n' "$BUMPED_LIST" | tr ',' '\n' | sed 's/^[[:space:]]*/- /')

## Test plan

- [ ] Confirm each \`plugin.json\` version bump matches the per-plugin tag that will be created after merge."
BASE="develop"
```

After inlining the push-or-pr snippet (steps 1–6 in that skill), branch on `$PUSH_RESULT`:

- `direct` — the bump commit is on origin's protected branch. Continue to Step 5.
- `pr` — push-or-pr opened `$PR_URL`. Self-review the PR, then merge it (`/flowkit:merge-pr` from `$NEW_BRANCH`). Once merged, switch to the protected branch and pull (`git checkout <branch> && git pull origin <branch>`), then continue to Step 5 — tags now point at the squash-merged commit, not the original feature-branch commit.
- `noop` — nothing changed. Stop and report.

### Step 5 — Create git tags

After the bump commit is on origin's protected branch (either via direct push or via merged PR), create a tag for each bumped plugin pointing at the current branch tip:

```bash
git tag {plugin-name}--v{new-version}
```

Do NOT push tags — leave that to the release flow.

### Step 6 — Detect new marketplace entries

Consumers who already have the marketplace registered locally will not see new plugins until they refresh their cache. Detect new plugin entries in `.claude-plugin/marketplace.json` since the last published release so the publisher can warn them.

Find the most recent repo-level release tag (calver `v*`, excluding per-plugin `*--v*` tags):

```bash
PREV_RELEASE_TAG=$(git tag --list 'v*' | grep -v -- '--v' | sort -V | tail -1)
```

Diff the marketplace plugin names between that tag and the working tree:

```bash
git show "${PREV_RELEASE_TAG}:.claude-plugin/marketplace.json" \
  | jq -r '.plugins[].name' | sort > /tmp/bv-prev-plugins
jq -r '.plugins[].name' .claude-plugin/marketplace.json | sort > /tmp/bv-curr-plugins
NEW_PLUGINS=$(comm -13 /tmp/bv-prev-plugins /tmp/bv-curr-plugins)
```

If `NEW_PLUGINS` is non-empty, emit a clearly formatted reminder block in the final report (Step 7). If `PREV_RELEASE_TAG` is empty (no prior release), skip silently.

### Step 7 — Report

Print a summary of what changed:

```
Bumped:
  swarmkit  1.0.0 → 2.0.0  (tag: swarmkit--v2.0.0)
  flowkit   1.0.0 → 1.1.0  (tag: flowkit--v1.1.0)

Tags created locally. Push with:
  git push origin --tags
```

If Step 6 detected new plugin entries, append a reminder block:

```
============================================================
NEW PLUGIN(S) DETECTED: squadkit
Consumers must refresh their marketplace cache after release:
  /plugin marketplace update smallorbit-plugins
Without this, `/plugin install <new>@smallorbit-plugins` fails
with "not found" because their cached index predates the edit.
============================================================
```

Substitute the actual new plugin names (comma-separated) and the marketplace name from `.claude-plugin/marketplace.json`'s `name` field.

## Notes

- Always read `plugin.json` before editing it (required by Edit tool).
- Increment only the relevant semver component; reset lower components to 0 (e.g. minor bump `1.2.3 → 1.3.0`).
- If a plugin has no per-plugin tag yet, its first tag will be created from the current `plugin.json` version (no bump required unless changes exist).
