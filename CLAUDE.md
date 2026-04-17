# smallorbit-plugins

Monorepo hosting Claude Code plugins: swarmkit, flowkit, sessionkit, and speckit.

## Release Process

Before every release, run `/bump-versions` to increment `plugin.json` versions for any plugins that have changed. This is required — without a version bump, existing users' clients won't pick up the updated code.

The bump-versions skill handles:
1. Detecting which plugins have changed since their last per-plugin tag
2. Asking for semver bump type (patch / minor / major) per plugin
3. Updating each `plugin.json`
4. Creating per-plugin git tags (`{plugin-name}--v{version}`)

Run it before staging and committing the release.

## GitHub Pages

`docs/index.html` is the source for the GitHub Pages one-pager at https://smallorbit.github.io/smallorbit-plugins/. When plugin versions change, update the version badges in the plugin cards section of that file to keep the site in sync.
