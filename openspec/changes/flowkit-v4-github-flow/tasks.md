# tasks

Implementation decomposition for flowkit v4. All tasks ship in a single coordinated PR.

## 1. flowkit v4 — rewrite core skills and prune deprecated ones

- [ ] Rewrite `plugins/flowkit/skills/ship/SKILL.md` for GitHub Flow:
  - Preflight: on `main`, local `main` in sync with `origin/main`, clean working tree, ≥1 commit since the last `v*` tag.
  - Derive next semver from conventional-commit prefixes across commits since the last tag (`BREAKING CHANGE`/`!` → major, `feat` → minor, else → patch).
  - Show the proposed tag to the operator for confirmation before pushing.
  - Tag HEAD of `main` (annotated tag), push the tag.
  - Create a GitHub Release via `gh release create` with auto-generated changelog (commits or PR titles since last tag).
- [ ] Rewrite `plugins/flowkit/skills/merge-pr/SKILL.md`:
  - Default merge mode flips from `--rebase` to `--squash`.
  - Drop the rebase-onto-base logic and the stacked-PR auto-retargeting block.
  - Keep the `with-clean-workspace` wrap.
  - Keep the auto-checkout-base safety net when the head branch is held by the main worktree.
  - Keep the caller-owned-worktree refusal.
- [ ] Rewrite `plugins/flowkit/skills/pr/SKILL.md`:
  - One-shot: commit-if-dirty → open PR against `main` (or `claude.flowkit.prBase` when set).
  - Drop the `create-branch` step (caller is responsible for branching off main, or `/pr` accepts a `--new-branch <name>` flag).
- [ ] Update `plugins/flowkit/skills/open-pr/SKILL.md`:
  - Default base is `main`, not `develop`.
  - Drop the `default-branch-prompt` sub-skill invocation.
  - Resolution chain becomes: `--base` arg → `claude.flowkit.prBase` config → `main`.
- [ ] Update `plugins/flowkit/skills/commit/SKILL.md`:
  - Verify message derivation is LLM-driven from the staged diff (no operator interview). Adjust if the current skill still prompts.
- [ ] Update `plugins/flowkit/skills/sync/SKILL.md`:
  - Replace `develop` references with `main`.
  - Behavior: pull `main`, prune stale remote-tracking refs, delete merged local branches (excluding `main` and current).
- [ ] Update `plugins/flowkit/skills/push-or-pr/SKILL.md`:
  - Default base becomes `main`.
- [ ] Update `plugins/flowkit/skills/pipeline-status/SKILL.md`:
  - Stages collapse to: open PRs → released. Drop "awaiting cut" and "awaiting release" stages.
  - Next-step priorities collapse accordingly.
- [ ] Delete skill directories: `create-branch`, `cut`, `release`, `ship-epic`, `cut-epic`, `pr-base-scope`, `default-branch-prompt`, `restack`.
- [ ] Verify the `with-clean-workspace` skill is untouched (still wrapped by the new `merge-pr`).

## 2. swarmkit — update for flowkit v4

- [ ] Rewrite `plugins/swarmkit/skills/swarm/SKILL.md`:
  - Replace `flowkit:cut-epic` invocation with an inline `git checkout -b feature/<slug>-<N> origin/main && git push -u origin feature/<slug>-<N>` block that also sets `claude.flowkit.prBase`.
  - All PR creation continues to honor `claude.flowkit.prBase`; the bottom-up merge order survives.
- [ ] Rewrite `plugins/swarmkit/skills/merge-stack/SKILL.md`:
  - Switch from `--rebase` to `--squash` merge mode.
  - Drop the "rebase downstream PR onto base after predecessor merges" step — squash-merge does not require fast-forward, so the downstream rebase only matters if conflicts arise (in which case the existing conflict-stops-chain scenario handles it).
- [ ] Audit `plugins/swarmkit/skills/swarm/SKILL.md` for references to removed flowkit skills (`cut`, `release`, `restack`, `ship-epic`, `cut-epic`, `pr-base-scope`, `default-branch-prompt`). Remove or replace.
- [ ] Verify `plugins/swarmkit/skills/clean-worktrees` and `clean-remote-worktrees` need no changes.

## 3. squadkit — update for flowkit v4

- [ ] Rewrite the epic-cutting block in `plugins/squadkit/skills/spawn-team/SKILL.md`:
  - Replace `Skill({skill: "flowkit:cut-epic", arguments: "<slug> <issue>"})` with inline `git`/`gh` calls that cut `feature/<slug>-<issue>` from `origin/main`, push it, and set `claude.flowkit.prBase`.
  - Preserve the cross-pin guard (refuse when an incompatible `feature/...` pin already exists).
  - Preserve idempotent reuse when the branch already exists on origin.
- [ ] Update the base-branch resolution in `spawn-team`:
  - Default fallback becomes `main`, not `develop`.
  - `.squadkit/config.json`'s `baseBranch` key still wins when present.
- [ ] Audit `plugins/squadkit/skills/spawn-team/SKILL.md` and `plugins/squadkit/skills/agent-team-retro/SKILL.md` for references to removed flowkit skills. Remove or replace.

## 4. Versions and documentation

- [ ] Bump `plugins/flowkit/.claude-plugin/plugin.json` to `4.0.0` (major).
- [ ] Bump `plugins/swarmkit/.claude-plugin/plugin.json` to the next minor (compat update).
- [ ] Bump `plugins/squadkit/.claude-plugin/plugin.json` to the next minor (compat update).
- [ ] Update `CLAUDE.md` "Canonical bubble-free release sequence" section to the new GitHub Flow sequence:
  ```
  /swarmkit:merge-stack    # land any open worktree-agent-* PRs (squash-merge into main)
  # verify on main         # typecheck/test/lint as appropriate
  /flowkit:ship            # tag main, create GitHub Release
  ```
- [ ] Update `README.md`:
  - Getting-started narrative: drop `develop`, drop RC concepts.
  - Plugin catalog: bumped versions.
- [ ] Update `plugins/flowkit/README.md`:
  - Skill list reflects the lean v4 surface.
  - Flow diagram updated for GitHub Flow.
- [ ] Update `plugins/swarmkit/README.md` and `plugins/squadkit/README.md`:
  - Drop references to develop/cut/release in any narrative or examples.
- [ ] Create `plugins/flowkit/MIGRATION-v4.md`:
  - v3 → v4 changeover guide.
  - Removed skill list and what to use instead.
  - Operator notes on archiving `develop`, `rc/*`, leftover `feature/<slug>-<N>` branches.

## 5. Migration helper + preflight detection

- [ ] Create `plugins/flowkit/skills/migrate-v4/SKILL.md`:
  - Detect: GitHub default branch (`gh repo view --json defaultBranchRef`), presence of `develop` / `rc/*` / legacy `feature/<slug>-<N>` branches on origin, any `claude.flowkit.defaultBranchPrompted` config key, any stale `claude.flowkit.prBase` pointing at a removed branch.
  - Plan: present the migration plan (steps + targets) before any mutation; operator confirms before execution.
  - Execute steps with per-step confirmation:
    1. Fetch latest develop and main (create local main if missing).
    2. Fast-forward main to develop's tip (`git merge develop --ff-only`); if non-FF, surface the divergence and ask before continuing.
    3. Push main.
    4. Switch GitHub default branch (`gh repo edit --default-branch main`).
    5. Delete `origin/develop`.
    6. Delete local develop.
    7. Unset legacy config keys (`claude.flowkit.defaultBranchPrompted`).
    8. Surface (do NOT auto-delete) any leftover `rc/*` and `feature/<slug>-<N>` branches on origin; leftover feature branches may contain unfinished work.
  - Idempotent: re-running on a fully-migrated repo reports "nothing to do" and exits zero.
- [ ] Add a preflight detection block to `plugins/flowkit/skills/ship/SKILL.md`:
  - Before the standard preflight, check if the GitHub default branch is `develop` (or `develop` exists on origin while `main` does not).
  - If legacy state detected, refuse with: `This repo is set up for flowkit v3 (develop/main split). Run /flowkit:migrate-v4 to migrate to single-trunk before using v4 skills.` Exit non-zero.
- [ ] Add the same preflight detection block to `plugins/flowkit/skills/pr/SKILL.md` (and any other v4 skill that mutates repo state).
- [ ] Expand `plugins/flowkit/MIGRATION-v4.md` (created in task 4) to document both paths:
  - Automated: `/flowkit:migrate-v4` (recommended).
  - Manual: step-by-step `git`/`gh` commands for operators who want to drive the migration themselves.

## 6. Post-merge follow-ups (not in this PR; tracked separately)

- [ ] File: rewrite `.claude/skills/ship-plugins.md` (repo-local) to use the new flowkit primitives instead of cut/release.
- [ ] File: re-baseline flowkit, swarmkit, squadkit-spawn-team specs via `/spec-baseline` once v4 lands so REFERENCES.md cites the new code.
- [ ] File: archive deprecated branches (`develop`, any open `rc/*`, any open `feature/<slug>-<N>` from the old flow) in this repo.
