# Base Branch Resolution

Canonical specification for PR base-branch resolution. Every plugin that calls `gh pr create` MUST resolve `$BASE` via this algorithm so the resolution order is consistent across the monorepo.

## Algorithm

Resolve `$BASE` in this order, stopping at the first non-empty result:

1. **Explicit caller arg** — if `$ARGUMENTS` contains a `--base <branch>` flag, extract and use it.
2. **Plugin-scoped config key** — read `git config claude.<plugin>.prBase`. Each plugin substitutes its own name (e.g. `claude.flowkit.prBase`, `claude.polishkit.prBase`).
3. **`develop` if it exists on the remote** — check with `git ls-remote --heads origin develop | grep -q 'refs/heads/develop'`.
4. **Repo default** — `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'`. Emit a one-line stderr warning before using this fallback.

## Post-condition

`$BASE` is always non-empty after step 4; consumers MUST pass `--base "$BASE"` to `gh pr create`. Never call `gh pr create` without an explicit `--base` — without it, gh falls through to the GitHub default branch (often `main`), which silently produces wrong-base PRs against repos that develop on a non-default branch.

## Plugin-scoped key naming rule

Each plugin owns exactly one key under its own namespace: `claude.<plugin>.prBase`. A plugin MUST NOT write to another plugin's scoped key. The separation ensures that a polishkit session pin cannot accidentally redirect flowkit PRs and vice versa.

## Cross-plugin courtesy interop (optional)

A consuming plugin MAY check a sibling plugin's scoped key as a courtesy slot — **after** its own scoped key (step 2) and **before** the `develop` fallback (step 3). This is an opt-in deviation; document it explicitly in the consuming skill. Example: polishkit checks `claude.flowkit.prBase` if its own `claude.polishkit.prBase` is unset, so a flowkit session pin propagates automatically when both plugins are installed together. The courtesy read is best-effort only — the consuming plugin works correctly without the sibling key present.

## Reference implementations

- [`plugins/flowkit/skills/open-pr/SKILL.md`](../flowkit/skills/open-pr/SKILL.md) — flowkit implementation (includes legacy `claude.prBase` deviation until [#896](https://github.com/smallorbit/smallorbit-plugins/issues/896) lands).
- [`plugins/polishkit/skills/polish/SKILL.md`](../polishkit/skills/polish/SKILL.md) — polishkit implementation (includes optional flowkit courtesy interop slot).

## Anti-patterns

- **Do not hardcode `develop`** — always use the resolution algorithm so repos without a `develop` branch fall through gracefully.
- **Do not skip the `$BASE` non-empty check** — an empty `$BASE` silently targets the GitHub default, which is almost always wrong in a feature-branch workflow.
- **Do not write to `claude.prBase`** — the legacy unscoped key is read-only for backward compatibility. All new writes go to `claude.<plugin>.prBase`.
- **Do not add new fallback layers without updating this doc first** — the algorithm is the contract; undocumented layers create invisible precedence conflicts across plugins.
