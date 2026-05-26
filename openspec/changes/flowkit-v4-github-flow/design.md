## Context

flowkit v3 prescribes a git-flow-classic-inspired flow: feature branches → rebase-merge to `develop` → cut `rc/YYYY-MM-DD.N` → rebase RC onto `main` → release PR → tag → close issues → cleanup. The model carries inherent friction:

- **Rebase-merge invariant**: every PR must be a fast-forward of its base at merge time. When a stacked PR's base advances, `gh pr merge --rebase` fails (`This branch can't be rebased`) and recovery requires local rebase + force-push. This session alone hit it on 5 PRs.
- **Multi-stage release ceremony**: per release we ship 1 RC branch, 1 RC tag, 1 release PR, 1 calver tag, ~4 per-plugin tags, multiple `gh issue close` calls, several force-pushes. Each is a step that can fail.
- **Failure modes specific to v3**: zsh `:r` parameter-modifier bug (#981), half-shipped-RC mid-release, stacked-PR rebase loop, RC retargeting after `develop` advances.

The flow exists for stabilization-window reasons that don't apply to a small-team plugin monorepo. Squash-merge collapses every release artifact except "tag on main + GitHub Release" and removes the rebase invariant entirely (GitHub computes the squash, no fast-forward required).

## Goals / Non-Goals

**Goals:**

- Eliminate the `develop`/RC/`main` split and the per-PR rebase ceremony it requires.
- Reduce release to a single command: `/flowkit:ship`.
- Preserve the bubble-free, linear-history invariant on `main` via squash-merge.
- Migrate the existing repo from v3 to v4 in a single coordinated PR — no deprecation window.
- Make flowkit a generic GitHub Flow plugin that external consumers can adopt without inheriting RC/epic-branch ceremony.

**Non-Goals:**

- Per-commit-in-PR bisectability (lost to squash-merge; PR-granularity bisect is sufficient).
- Migration of pre-existing `feature/<slug>-<N>` epic branches or open `rc/*` branches in the wild — v4 abandons them in place; the operator finishes or deletes manually before installing v4.
- Marketplace mechanics rewrite (per-plugin tags, marketplace.json change detection, consumer install paths). Repo-local `/ship-plugins` rewrite is a separate change.
- CI / GitHub Actions changes.
- A deprecation window for external consumers (external adoption is negligible today).

## Decisions

### D1: Squash-merge as the canonical merge mode

Every PR squash-merges to `main`. Never rebase-merge, never merge-commit. Rationale:

- **No fast-forward requirement** → no stacked-PR rebase failures. GitHub's tree-based diff handles already-applied predecessor commits when a parent PR merges first; descendants apply cleanly on next merge attempt without local rebase or force-push.
- **Linear first-parent history on `main`** preserved — one commit per PR, ordered.
- **PR-granularity bisect** retained. The squashed commit message contains the PR body summary; GitHub auto-links back to the PR from the commit footer.

Alternatives rejected: merge-commit (loses linearity), rebase-merge (the invariant we're trying to escape).

### D2: Single `ship` command, no `cut → release` chain

`/flowkit:ship` is the only release skill. It preflights (main+sync+clean+progress), derives semver from conventional commits since the last `v*` tag, tags HEAD of `main` annotated, pushes the tag, and creates a GitHub Release with `--generate-notes`.

Rationale: with no `develop`/RC/`main` split, there is no stabilization branch to cut and no separate "promote RC to main" step. The release is whatever's on `main` *right now*.

Alternative rejected: `cut → release` chain inherited from v3. Reasoning: it exists only because v3 has an RC stabilization stage. v4 has none.

### D3: Conventional-commit-driven semver derivation

Ship reads commits since the last `v*` tag, scans for conventional-commit type tokens, and picks the bump:

- Any `BREAKING CHANGE:` or `!:` → **major**
- Any `feat` → **minor**
- Otherwise → **patch**

Operator confirms the proposed tag before any push. The bump rationale is shown alongside the proposal.

Rationale: deterministic, reads from data the operator already authors (commit messages), no separate version-decision UI to maintain.

Alternative rejected: prompt the operator for the bump type each release. Reasoning: the type is *already* in the commits — re-asking is friction.

### D4: Coordination primitives move out of flowkit

`cut-epic`, `ship-epic`, `pr-base-scope`, `default-branch-prompt`, `restack`, `create-branch`, and `release` are all removed. The remaining surface is:

- `commit`, `pr`, `open-pr`, `merge-pr` — single-PR lifecycle
- `sync`, `with-clean-workspace`, `push-or-pr` — workspace + sync primitives
- `ship` — release
- `pipeline-status` — read-only stage display
- `migrate-v4` — v3 → v4 helper

Callers that need multi-PR coordination (squadkit, swarmkit) cut their own `feature/<slug>-<N>` branches inline via `git`/`gh`. They pin `claude.flowkit.prBase` directly so flowkit's `Base Branch Resolution` chain picks it up.

Rationale: flowkit's job is git-flow primitives. Multi-PR coordination is a dispatch concern (squad/swarm). Mixing the two into flowkit made flowkit specific to this monorepo's plugin-release model. Separating them makes flowkit reusable.

Alternative rejected: keep `cut-epic` as a flowkit primitive and have callers invoke it. Reasoning: every caller needs a slightly different cut-epic shape (squadkit cuts at spawn time, swarmkit cuts at first-non-empty-cycle). The shared "primitive" became thin glue around copy-pasted `git`/`gh` calls. Inlining is simpler.

### D5: Preflight Migration Check scope — ship + pr only

Only `/flowkit:ship` and `/flowkit:pr` refuse to run on a develop-default repo. Other skills (`commit`, `sync`, `pipeline-status`) proceed without the check.

Rationale: the migration helper exists to keep operators from corrupting state. Only mutating skills can corrupt state. Read-only or workspace-local skills don't need the gate.

Alternative rejected: gate every v4 skill on the migration check. Reasoning: adds noise to skills that can't break, and would make `pipeline-status` (the recommended first command on an unfamiliar repo) fail confusingly.

### D6: Migrate-v4 is interactive, idempotent, and never auto-deletes feature branches

The migration helper:

1. Detects legacy state (develop default, develop branch on origin without main, RC branches, legacy config keys).
2. Presents a full plan before any mutation.
3. Confirms each destructive step individually (default-branch switch, develop deletion, RC deletion).
4. Surfaces leftover `feature/<slug>-<N>` branches in the plan but does NOT auto-delete them (they may contain unfinished work).
5. Re-running on an already-migrated repo reports "nothing to do" and exits zero.

Rationale: the migration is destructive (renaming the default branch can't be undone trivially). Operator control over each step is non-negotiable.

Alternative rejected: fully automatic migration. Reasoning: even with confirmations on the helper itself, branch deletion of `feature/*` branches risks losing unmerged work the operator didn't realize was still relevant.

### D7: Wholesale, single-PR migration in this repo

The v4 PR coordinates flowkit + swarmkit + squadkit updates together. No deprecation window. Reasoning:

- All three plugins live in this monorepo. There is no external consumer who needs lead time.
- A staged rollout (flowkit v4 first, swarmkit/squadkit chasers later) would leave the monorepo in a broken state during the gap — swarmkit's `Feature-Branch Mode` and squadkit's `Epic Branch Cutting` directly invoke flowkit primitives that no longer exist in v4.
- Single PR is testable end-to-end (run a verify pass on the integrated branch before merging).

Alternative rejected: phased migration with shim. Reasoning: the shim costs more code than the migration it deprecates. The repo is small enough that wholesale is feasible.

### D8: External `flowkit` consumers eat the breaking change

v4 is a hard break for any external consumer. The release notes call it out explicitly. No deprecation period.

Rationale: external adoption is currently negligible. The cost of maintaining a v3 deprecation path is real (parallel code paths, dual-test); the benefit (one or two unknown consumers' convenience) is hypothetical.

Alternative rejected: ship `flowkit@4` alongside `flowkit@3` for one minor release. Reasoning: doubles maintenance for an unknown user base.

## Risks / Trade-offs

- **[Risk]** PR rebase-merge gets accidentally re-enabled by an operator on a branch protection rule somewhere. → **Mitigation**: `PR Merge` requirement is explicit that the call is `gh pr merge --squash --delete-branch`; the merge-pr skill never accepts a `--rebase` flag.

- **[Risk]** Operators with v3 muscle memory type `/flowkit:cut` or `/flowkit:release` and get confusing "skill not found" errors. → **Mitigation**: `MIGRATION-v4.md` under `plugins/flowkit/` documents v3 → v4 commands. First-run telemetry of removed skills (if added) could surface remaining v3 usage patterns.

- **[Risk]** Repo-local `/ship-plugins` (which chains `merge-stack → bump-versions → cut → release`) breaks at v4 install time. → **Mitigation**: explicit out-of-scope in the proposal. Plugins ship manually via `/bump-versions` + `/flowkit:ship` until `/ship-plugins` is rewritten in a follow-up change.

- **[Risk]** `/flowkit:migrate-v4` is destructive and could misdetect legacy state. → **Mitigation**: plan presented before any mutation; per-step confirmation on destructive operations; idempotent re-runs; feature branches never auto-deleted. The skill is itself a v4 skill — operators run it once per repo at migration time, not in steady state.

- **[Trade-off]** Per-commit-in-PR bisectability lost. → **Acceptable**: PRs in this monorepo are usually one logical change. The commit body of the squash retains the per-commit messages as context.

- **[Trade-off]** No RC stabilization window. → **Acceptable**: the monorepo doesn't ship to a wide consumer base in a release rhythm that justifies RC stabilization. The "RC" in v3 was a one-day window between cut and release with no actual review activity.

- **[Trade-off]** External adoption of flowkit is held hostage to one breaking change with no grace period. → **Acceptable** given current adoption levels. Re-evaluate if external users emerge.

## Migration Plan

1. **Pre-merge verification**: integrate the v4 PR locally, run smoke tests of `/flowkit:ship`, `/flowkit:pr`, `/flowkit:merge-pr`, `/flowkit:sync`, `/squadkit:spawn-team`, `/swarmkit:swarm-plus` against a scratch fork to confirm coordination still works.
2. **Merge order**: the v4 PR is the single landing artifact. Merge to `main` via existing v3 flow (last v3 release).
3. **First v4 release**: run `/flowkit:migrate-v4` on this repo to switch the default branch from `develop` to `main` and delete `develop`. Then run `/flowkit:ship` for the v4 launch tag.
4. **External consumers**: post v4 release notes prominently calling out the breaking change. Provide a one-line migration: "run `/flowkit:migrate-v4` once."
5. **Rollback**: revert the v4 merge commit. Operators on v4 already revert via `/flowkit:migrate-v4`'s inverse (re-enable develop default, restore develop branch from a recent commit on main). Document the rollback path in `MIGRATION-v4.md`.

## Open Questions

1. **Should `/flowkit:migrate-v4` also archive `develop`'s branch protection rules?** Branch protection on `develop` becomes dead config after migration. → **Recommendation**: surface in the migration plan as informational; do not auto-delete (GitHub branch protection is operator-owned policy).

2. **What's the `/flowkit:ship` behavior on a force-pushed `main`?** If `origin/main` and local `main` diverge (force-push by another operator), ship's preflight fails. → **Recommendation**: explicit error directing operator to `git pull --rebase origin main` and re-verify the tag rationale before retrying. Do not auto-pull.

3. **Should `Conventional Commit Format` enforce scope?** Today scope is optional in the format token. → **Recommendation**: keep optional. Scope is a quality concern, not a correctness concern; LLM-derived scope handles the common case.

4. **Per-plugin tags after v4**: the existing `{plugin}--v{version}` tag convention is still needed for marketplace consumption. → **Recommendation**: out of scope for v4; `/bump-versions` continues to create these tags, decoupled from `/flowkit:ship` which only creates the calver-or-semver release tag for the repo as a whole. The `/ship-plugins` rewrite (separate change) will integrate the two.
