# Handoff

**Project**: /Users/roman/src/smallorbit-plugins
**Date**: 2026-04-16
**Branch**: develop

## Goal
Ongoing maintenance of the smallorbit-plugins repo — fixing bugs found in live
usage of swarmkit and flowkit, and shipping them through a full release cycle.

## Progress
- Added flowkit, sessionkit, and speckit to marketplace.json (PR #24, released)
- Fixed release skill to aggregate `Closes #N` refs into release PR body (PR #26, released)
- Fixed swarm plan auto-proceed delay 60s → 30s (PR #30, released)
- Fixed release skill to filter merged PRs by tag date (PR #31, released — but still has bugs, see Remaining Work)
- Hardened clean-worktrees: double-force removal, prune-first, cd-to-root (PR #32, released)
- Released all of the above as `v2026.4.16`
- Filed issues #34, #35, #36 for known remaining bugs

## Git State
- Branch: develop (in sync with main at v2026.4.16)
- Staged: none
- Unstaged: none
- Recent commits:
  - `70b5e78` fix(swarmkit): harden clean-worktrees (#32)
  - `25ce224` fix(flowkit): filter merged PRs by tag date (#31)
  - `0172df7` fix(swarmkit): reduce swarm plan auto-proceed delay (#30)
  - `1d03c5b` fix(flowkit): aggregate Closes references into release PR body (#26)
  - `f4e03d7` feat(marketplace): add flowkit, sessionkit, and speckit plugins (#24)

## Remaining Work
1. **#35 (high/bug)** — Release step 4 still broken: `--base "$SOURCE"` should always be `--base develop`; jq `--arg` syntax doesn't work in `gh pr list` — needs shell string interpolation
2. **#36 (medium/enhancement)** — Auto-close epics by appending `Closes #epic` to release PR body; remove `gh-close-referenced-issues` sub-skill once done
3. **#34 (medium/bug)** — Audit all skill files for `for N in $VAR` and replace with `while read N` piped pattern

## Context
- Staging branch exists on this repo (`develop → staging → main` flow)
- Release works by force-pushing an RC branch to staging, then opening a PR staging → main
- `gh-close-referenced-issues` sub-skill is now partially redundant: GitHub auto-closes issues referenced in the release PR body. The sub-skill's only remaining value is epic auto-close (step 6) — which #36 proposes to replace with native GitHub behavior
- The `gh pr list --jq --arg` syntax silently fails; always use shell string interpolation for variable injection into jq expressions
- `--base staging` returns empty because staging is force-pushed, not PR-merged; always use `--base develop` for issue ref aggregation
- All agent worktrees use double-force removal (`-f -f`) now — needed for claude-agent-locked worktrees
