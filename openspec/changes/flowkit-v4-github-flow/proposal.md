# flowkit v4: GitHub Flow

## Status

Draft. Authored 2026-05-25 against the flowkit, swarmkit, and squadkit-spawn-team baseline specs landed in PRs #975/#976/#977/#978.

## Problem

flowkit currently prescribes a git-flow-classic-inspired model: feature branches → rebase-merge to `develop` → cut `rc/YYYY-MM-DD.N` → rebase the RC onto `main` → release PR → tag → close issues → cleanup. Every release requires a multi-step git "dance" with several force-pushes, an RC branch, an RC tag, a release PR against `main`, a calver tag, per-plugin tags, and explicit `gh issue close` calls. The rebase-merge invariant — every PR must be a fast-forward of its base at merge time — means each stacked PR independently fails `gh pr merge --rebase` whenever the base advances, requiring local-rebase + force-push to recover.

Concretely, in a single session (the one that produced this proposal):

- All four stacked PRs (#975, #976, #977, #978) failed `gh pr merge --rebase` with `This branch can't be rebased` and required local rebase + force-push.
- The bump-versions PR (#979) hit the same failure when `develop` advanced under it.
- The release PR (#980) required an unconditional rebase of the RC onto `main` and then triggered the zsh `:r` parameter-modifier bug because `release/SKILL.md`'s example used unbraced `$SOURCE` (see #981).
- Total per release: 1 RC branch, 1 RC tag, 1 release PR, 1 calver tag, ~4 per-plugin tags, several `gh issue close` calls, and 4+ force-pushes — none of which add user-facing value over GitHub Flow.

For a small-team plugin monorepo, the `develop` / `main` split offers no stabilization advantage that justifies its cost. GitHub Flow with squash-merge (the dominant pattern in trunk-based shops) eliminates server-side rebase dances — GitHub computes the squash, no fast-forward required — and collapses the release flow to "tag HEAD of main and create a GitHub Release."

## Approach

Replace the `develop`/RC/`main` model with single-trunk GitHub Flow. Feature branches PR into `main`, squash-merge, and the next release is just a tag on `main`. The cut/release/ship-epic/cut-epic skill chain dissolves into a single `/flowkit:ship` that preflights main, derives the next semver from conventional commits, tags `main`, and creates a GitHub Release with an auto-generated changelog.

flowkit's lean v4 surface:

| Skill | v4 status |
|-------|-----------|
| `commit` | Kept. LLM-derives a conventional-commit message from the staged diff. No operator interview. |
| `pr` | Kept. One-shot: commit-if-dirty → open PR against main (or against `claude.flowkit.prBase` when pinned). |
| `open-pr` | Kept. Primitive used by `pr`; protected-branch check stays. Base default is `main`, not `develop`. |
| `merge-pr` | Kept. Defaults to `--squash`. Drop rebase-onto-base logic and stacked-PR retargeting machinery — squash-merge doesn't require fast-forward. |
| `sync` | Kept. Pull `main`, prune, delete merged local branches. |
| `with-clean-workspace` | Kept. Workspace stash guard, unchanged. |
| `push-or-pr` | Kept. Default base becomes `main`. |
| `pipeline-status` | Kept. Stages collapse: in-flight PRs → released. No "awaiting cut" or "awaiting release" stages. |
| `ship` | **Rewritten.** Single skill: preflight (on main, in sync, clean tree, commits since last tag) → derive next semver from conventional commits → tag HEAD of main → push tag → create GitHub Release with auto-generated changelog. Refuses to run on a develop-default repo and points to `migrate-v4`. |
| `migrate-v4` | **New.** One-shot interactive helper for repos currently on the v3 develop/RC/main flow. Detects legacy state, presents a migration plan, executes step by step with operator confirmation. Idempotent. |
| `create-branch` | **Removed.** Operator creates branches inline; `pr` handles the common case. |
| `cut` | **Removed.** No RC branches. |
| `release` | **Removed.** Replaced by the rewritten `ship`. |
| `ship-epic` | **Removed.** No develop/epic-promotion hierarchy. |
| `cut-epic` | **Removed.** Callers (squadkit, swarmkit) cut feature branches inline via `git`/`gh` when they need multi-PR coordination. |
| `pr-base-scope` | **Removed.** Operator manages the `claude.flowkit.prBase` pin directly via `git config`. |
| `default-branch-prompt` | **Removed.** Only `main` matters under GitHub Flow. |
| `restack` | **Removed.** Squash-merge eliminates the stacked-rebase use case. |

Coordinated multi-PR work survives via `claude.flowkit.prBase` (set by swarmkit/squadkit when they cut a `feature/<slug>-<N>` branch inline), which `pr` and `open-pr` honor as a PR base override. swarmkit's `merge-stack` still merges bottom-up but with squash semantics — the rebase choreography that exists only because of the rebase-merge invariant disappears.

The "bubble-free" invariant on `main` is preserved by squash-merge (one commit per PR, linear history) — without the rebase dance. Bisectability is preserved at PR granularity rather than per-commit-in-PR.

## Why this matters

Operationally:
- A release goes from ~15 steps + 4 force-pushes to: `/flowkit:ship`. One command, one tag, one GitHub Release.
- The stacked-PR rebase failure (4 instances this session) disappears entirely.
- The zsh `:r` refspec bug class (#981) goes away — no force-push refspecs to brace.
- The half-shipped-RC failure mode (release SKILL.md step 5.5) goes away — no RC to half-ship.
- The deprecated `develop` branch and any `rc/*` / `feature/*` cruft can be archived or deleted.

Architecturally:
- flowkit becomes a generic GitHub Flow git-flow plugin rather than a custom git-flow-classic clone, so consumers other than this monorepo can adopt it without inheriting RC/epic-branch ceremony.
- Repo-local marketplace ceremony (per-plugin tags, plugin.json bumps, `/ship-plugins`) is decoupled from flowkit. It stays repo-local under `.claude/skills/` and gets a follow-up redesign that builds on the new primitives.

Strategically:
- This is the textbook trunk-based development model. Industry standard, well-understood, low onboarding cost for any operator who's used GitHub Flow elsewhere.
- The bubble-free invariant survives via squash-merge — the elegance argument for `main` history holds, achieved by a simpler mechanism.

## Out of scope

- The repo-local `/ship-plugins` skill rewrite. Stays as-is for now; gets its own change proposal once v4 is merged. (It currently chains merge-stack → bump-versions → cut → release; the cut/release calls must be replaced.)
- The repo-local `/bump-versions` skill. Stays as-is; marketplace concerns remain repo-local.
- Marketplace mechanics (per-plugin tags, marketplace.json change detection, consumer install paths).
- GitHub Actions / CI changes.
- Migration of any pre-existing `feature/<slug>-<N>` epic branches or open `rc/*` branches in the wild — v4 abandons them in place; operators can finish or delete them manually before installing v4.
- The auto-rebase fallback issue surfaced in this session's retro — it would be a band-aid on a deprecated flow and is not filed.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| swarmkit/squadkit break in the v4 PR if not updated atomically | Single coordinated PR ships flowkit v4 + swarmkit/squadkit updates together. No deprecation window because consumers live in the same monorepo. |
| Operators with muscle memory for the old commands hit removed skills | The first ship of v4 will log clear "removed in v4, use /flowkit:ship" messages. A `MIGRATION-v4.md` lives under `plugins/flowkit/` documenting v3 → v4. |
| Repos already configured for v3 (develop as the GitHub default, `develop` branch on origin, RC branches in flight) fail confusingly under v4 skills | A new `/flowkit:migrate-v4` skill detects legacy state and walks the operator through the migration interactively (fast-forward main to develop, switch default branch, delete develop, surface leftover feature/RC branches). v4 skills that mutate repo state (ship, pr) refuse to run on a develop-default repo and point at `migrate-v4`. |
| External consumers using flowkit v3 don't get a deprecation window | Acceptable: flowkit's external adoption is currently negligible; the v4 release notes call out the breaking change explicitly. |
| Squash-merge loses per-commit granularity inside a PR | Acceptable: PRs in this monorepo are usually one logical change. The commit message inside the PR is preserved as the squashed commit message on main, and the PR itself stays visible from main's commit footer. |
| Repo-local `/ship-plugins` breaks until rewritten | Acceptable: `/ship-plugins` is shipped from `.claude/skills/` and is repo-local — it will be rewritten in a follow-up change proposal between v4 merge and the next plugin release. Until then, operators ship plugins manually using `/bump-versions` + `/flowkit:ship`. |

## Affected specs

This change proposes new end-state specs for:

- `openspec/specs/flowkit/spec.md` — substantial rewrite; ~half the requirements removed, several modified, one new (`Ship` is conceptually different from v3's "Ship Closer").
- `openspec/specs/swarmkit/spec.md` — modified `Feature-Branch Mode` (cut-epic invocation becomes inline), modified `Bottom-Up Stack Merge` (drop the rebase-after-merge step that existed only because of rebase-merge invariant), all other requirements unchanged.
- `openspec/specs/squadkit-spawn-team/spec.md` — modified `Main Repo Root and Base Branch Resolution` (default falls through to `main`, not `develop`), modified `Epic Branch Cutting and Cross-Pin Guard` (cut-epic invocation becomes inline `git`/`gh` calls), all other requirements unchanged.

End-state spec files live under `openspec/changes/flowkit-v4-github-flow/specs/`. On merge, they replace the matching files under `openspec/specs/`. REFERENCES.md files get re-derived against the new implementation via `/spec-baseline` after v4 lands.
