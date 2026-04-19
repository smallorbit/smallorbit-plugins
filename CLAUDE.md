# smallorbit-plugins

Monorepo hosting Claude Code plugins. See the [repo README](./README.md#available-plugins) for the current plugin catalog — it's the canonical source and stays in sync as plugins ship.

## Release Process

Before every release, run `/bump-versions` to increment `plugin.json` versions for any plugins that have changed. This is required — without a version bump, existing users' clients won't pick up the updated code.

The bump-versions skill handles:
1. Detecting which plugins have changed since their last per-plugin tag
2. Asking for semver bump type (patch / minor / major) per plugin
3. Updating each `plugin.json`
4. Creating per-plugin git tags (`{plugin-name}--v{version}`)

Run it before staging and committing the release.

## Plugins

`swarmkit` includes an experimental `squad` skill gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. See `plugins/swarmkit/README.md` for details.

## Skill Authoring Conventions

**Bash loop convention**: Never use `for N in $VAR` to iterate over newline-delimited output — word splitting is unreliable across shell contexts. Always pipe directly: `some-command | while read N; do ... done`.

## metakit kit detection

metakit composes sibling kits into multi-step scenarios. It determines which kits are "installed" by reading Claude Code's `settings.json` from two scopes:

- **User scope** — `~/.claude/settings.json` (and `~/.claude/settings.local.json` when present)
- **Project scope** — `.claude/settings.json` (and `.claude/settings.local.json` when present) relative to the current working directory

A kit is considered available when its plugin id (e.g. `speckit`, `swarmkit`, `polishkit`, `flowkit`, `sessionkit`, `vaultkit`) is enabled in either scope. Project scope wins on conflict — an enabled kit in the project file overrides a disabled one in the user file, and vice versa.

When authoring a new scenario (a skill under `plugins/metakit/skills/`), validate it against both scopes:

1. Temporarily disable a kit your scenario depends on in one of the `settings.json` files above.
2. Run the scenario and confirm it degrades gracefully — the preview marks the step as skipped, the remaining steps still run, and no step fails because the kit is absent.
3. Re-enable and confirm the full path runs end-to-end.

Every scenario must honor the halt-and-report failure contract: on any step failure, stop the scenario and emit a state report (what ran, what didn't, enough context for another agent to resume). Never continue past a failure silently.
