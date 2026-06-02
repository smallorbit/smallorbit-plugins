# Base Branch Resolution

Canonical specification for PR base-branch resolution. Every plugin that opens a PR (or cuts a branch that a PR will later target) MUST resolve `$BASE` via this chain so the resolution order stays consistent across the monorepo.

This monorepo runs a **single-trunk** workflow: `main` is the integration branch and the repo default. There is no `develop`. The resolution chain below reflects that reality — the terminal fallback is a hardcoded `main`, not a `develop` probe or a `gh repo view` default lookup.

## Algorithm

Resolve `$BASE` in this order, stopping at the first non-empty result:

1. **Explicit caller arg** — if `$ARGUMENTS` contains a `--base <branch>` flag, extract and use it.
2. **Plugin-scoped config key** — read `git config claude.<plugin>.prBase`. Each plugin substitutes its own name (e.g. `claude.flowkit.prBase`, `claude.polishkit.prBase`). Epic flows (squadkit `--epic`, flowkit `cut-epic`) pin this key to the long-lived feature branch so member PRs target the epic automatically.
3. **`main`** — the single-trunk default. Hardcoded; no `develop` probe and no `gh repo view` default lookup.

A plugin MAY accept `main` as a build-time default rather than resolving it at step 3 (swarmkit's preflight sets `BASE="main"` before parsing args, then lets `--base` override it). The observable precedence is identical: explicit arg wins, then the scoped pin, then `main`.

## Post-condition

`$BASE` is always non-empty after step 3; consumers MUST pass `--base "$BASE"` to `gh pr create`. Never call `gh pr create` without an explicit `--base` — without it, gh falls through to the GitHub default branch, which is fine today (it is `main`) but couples the PR target to repo settings instead of this contract.

Consumers SHOULD also guard that the resolved `$BASE` is not the current HEAD branch. This catches the case where an epic branch has `claude.flowkit.prBase` pinned to itself — opening a PR from a branch against itself is always wrong. flowkit's open-pr errors out with remediation hints (override with `--base main`, or unset the pin) when `$BASE` equals HEAD.

## Plugin-scoped key naming rule

Each plugin owns exactly one key under its own namespace: `claude.<plugin>.prBase`. A plugin MUST NOT write to another plugin's scoped key. The separation ensures that a polishkit session pin cannot accidentally redirect flowkit PRs and vice versa.

## Cross-plugin courtesy interop (optional)

A consuming plugin MAY check a sibling plugin's scoped key as a courtesy slot — **after** its own scoped key (step 2) and **before** the `main` default (step 3). This is an opt-in deviation; document it explicitly in the consuming skill. Example: polishkit checks `claude.flowkit.prBase` if its own `claude.polishkit.prBase` is unset, so a flowkit session pin propagates automatically when both plugins are installed together. The courtesy read is best-effort only — the consuming plugin works correctly without the sibling key present.

## Reference implementations and consumers

- [`plugins/flowkit/skills/open-pr/SKILL.md`](../flowkit/skills/open-pr/SKILL.md) — faithful reference for the three-step chain: `--base` arg → `claude.flowkit.prBase` → hardcoded `main`, plus the HEAD-equals-base guard.
- [`plugins/polishkit/skills/polish/SKILL.md`](../polishkit/skills/polish/SKILL.md) — resolves base before dispatching its worker, with its own `claude.polishkit.prBase` at step 2 and the optional `claude.flowkit.prBase` courtesy interop slot.
- [`plugins/swarmkit/skills/swarm/scripts/preflight.sh`](../swarmkit/skills/swarm/scripts/preflight.sh) — defaults `BASE="main"` and accepts `--base <branch>` (no scoped-key read). It additionally seeds the base branch on origin from the repo default if the resolved base is missing. The swarm flow passes the resolved base through to `gh pr create --base` directly.
- [`plugins/squadkit/skills/spawn-team/SKILL.md`](../squadkit/skills/spawn-team/SKILL.md) — reads `baseBranch` from `.squadkit/config.json` (defaulting to `main`), cuts the epic `feature/<slug>-<issue>` branch from `origin/main`, and pins `claude.flowkit.prBase` to the epic so each member's `flowkit:open-pr` resolves the epic at step 2. Squadkit itself does not call `gh pr create`; it defers PR creation to flowkit via the pinned key.

## Anti-patterns

- **Do not reintroduce a `develop` probe or `gh repo view` default lookup** — this repo is single-trunk on `main`. The terminal fallback is a hardcoded `main`. Hardcoding `main` at step 3 is correct and intentional, not an anti-pattern.
- **Do not skip the `$BASE` non-empty check** — although step 3 always yields `main`, consumers must still pass `--base "$BASE"` explicitly rather than relying on gh's implicit default.
- **Do not target a non-`main` branch implicitly** — only an explicit `--base` arg or a deliberately set scoped pin may redirect away from `main`. Never infer the base from ambient repo state.
- **Do not write to or rely on `claude.prBase`** — the unscoped legacy key is no longer read by any plugin. All writes go to `claude.<plugin>.prBase`.
- **Do not add new fallback layers without updating this doc first** — the chain is the contract; undocumented layers create invisible precedence conflicts across plugins.
