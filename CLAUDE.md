# smallorbit-plugins

Monorepo hosting Claude Code plugins. See the [repo README](./README.md#available-plugins) for the current plugin catalog — it's the canonical source and stays in sync as plugins ship.

## User-Facing Docs

The root [README](./README.md) owns two canonical anchors that other surfaces cross-link to rather than duplicate:

- `#available-plugins` — plugin catalog.
- `#getting-started` — end-to-end walkthrough for new users (prereqs → install → `/spec` → `/swarm` → ship).

The landing page (`docs/index.html`) and each plugin README link back to these anchors instead of carrying parallel copies. When updating onboarding narrative, edit the root README and let the teasers point to it — don't fork the walkthrough into individual plugin READMEs.

## Release Process

Before every release, run `/bump-versions` to increment `plugin.json` versions for any plugins that have changed. This is required — without a version bump, existing users' clients won't pick up the updated code.

The bump-versions skill handles:
1. Detecting which plugins have changed since their last per-plugin tag
2. Asking for semver bump type (patch / minor / major) per plugin
3. Updating each `plugin.json`
4. Creating per-plugin git tags (`{plugin-name}--v{version}`)

Run it before staging and committing the release.

### Canonical bubble-free release sequence

```
/swarmkit:merge-stack            # land all open worktree-agent-* PRs into main
# verify on main — run typecheck/test/lint as appropriate
/flowkit:ship                    # tag HEAD of main, push tag, create GitHub Release
```

`/flowkit:ship` refuses to run while open `worktree-agent-*` PRs target main — operators land those via `/swarmkit:merge-stack` first so the verify gate can run against the integrated snapshot before shipping. For releases with no swarm in flight, `/flowkit:ship` runs unconditionally.

When work originates as an OpenSpec change, `opsx-bridge` can dispatch its implementation into the squad or swarm flow that produces the epic and `worktree-agent-*` PRs this sequence later integrates and ships (see the Plugins section below).

## Plugins

`squadkit` is the interactive multi-role collaboration plugin (sibling to swarmkit's parallel-issue resolution). It introduces the `roles → squads → crews` vocabulary and ships `spawn-team`, `init`, and a `SessionStart` hook that re-asserts role context on resume.

**Crew shapes.** Crew profiles carry an optional `kind:` field — `execution` (default) for crews that ship code, `discovery` for read-only research crews that produce blueprint comments on GitHub issues instead of PRs. Discovery crews skip worktree provisioning, epic-branch cutting, and `claude.flowkit.prBase` pinning. See [`plugins/squadkit/docs/patterns/discovery-coordination.md`](./plugins/squadkit/docs/patterns/discovery-coordination.md) for the architect-led coordination pattern.

**Base-branch convention.** Execution crews always work on a `feature/<slug>-<issue>` branch cut from `main`, owned by `spawn-team`. They never commit directly to `main`. Discovery crews stay on `main` since they don't produce code.

`opsx-bridge` connects OpenSpec changes to those same dispatchers. It is purely additive — it leaves opsx, squadkit, and swarmkit untouched, calling them through their existing skill surface. Given a proposed `openspec/changes/<name>/`, `opsx-bridge:apply-via-squad <change>` derives a squad profile from the proposal's `## Capabilities` and dispatches via `/squadkit:spawn-team`, while `opsx-bridge:apply-via-swarm <change>` maps each `tasks.md` section to a GitHub issue and dispatches via `/swarmkit:swarm`. These are the multi-agent alternative to stock single-agent `/opsx:apply`. See [`plugins/opsx-bridge/README.md`](./plugins/opsx-bridge/README.md).

## Skill Authoring Conventions

**Before authoring** a new skill, adding a script under `scripts/`, or substantially rewriting a `SKILL.md` under `plugins/`, read the canonical convention docs that apply:

- New script under `plugins/<plugin>/skills/<skill>/scripts/` → [`plugins/_shared/script-authoring.md`](./plugins/_shared/script-authoring.md)
- Skill or script that opens a PR → [`plugins/_shared/pr-body.md`](./plugins/_shared/pr-body.md)
- New skill or cross-plugin pattern → both of the above
- Skill with blast-radius decisions (git state, PRs, labels) → [`plugins/_shared/eval-authoring.md`](./plugins/_shared/eval-authoring.md)

Skip for typo fixes, renames, and small edits that don't touch convention surfaces.

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.

**PR body standard**: All PRs opened by agents in this repo must follow the canonical three-section shape (`## Summary`, `## Changes`, `## Test plan`) plus an issue-reference footer. The spec lives at [`plugins/_shared/pr-body.md`](./plugins/_shared/pr-body.md) — reference it instead of inventing a local format.

**Skill scripts standard**: Skills that extract deterministic bash work into shell scripts must follow the convention at [`plugins/_shared/script-authoring.md`](./plugins/_shared/script-authoring.md) — folder layout, `$SKILL_DIR` resolution, bare-payload JSON, stderr errors, when to extract, and `.claude/settings.json` allowlist guidance.

**CI gates (skill evals)**: Two required checks run on every PR via `.github/workflows/skills-ci.yml` and enforce the conventions above — see [`evals/README.md`](./evals/README.md). **L1** (`scripts/test-all-skill-scripts.sh`) runs every `plugins/*/skills/*/scripts/test.sh`; a script-backed skill with a missing or failing `test.sh` blocks merge. **L2** (`scripts/lint-skills.py`) lints skill-doc structure — frontmatter, include/`_shared` citation/relative-link resolution, no stale `develop` references, and `.claude/settings.json` allowlist paths. Run `python3 scripts/lint-skills.py` locally before pushing.

**README flag-matrix drift**: Any change to a SKILL.md `## Input` table needs a matching pass on the corresponding plugin README's flag matrix — these drift silently otherwise. The L2 linter surfaces undocumented flags as warnings.

**Spec scope — always include docs**: When speccing any code change, the task list must include explicit tasks for updating all affected documentation and specifications (plugin READMEs, `CLAUDE.md`, OpenSpec `spec.md`, site content, `marketplace.json`). Do not treat documentation updates as implied — file them as discrete tasks so they survive the catalog and are not silently dropped.
