---
name: clean-stale-teams
description: Prune stale squadkit team registries under ~/.claude/teams/. Scans each session team dir, classifies which are safe to remove (only an in-process lead, no spawned members, no live worktrees), shows the verdict, and deletes the orphans. Complements clean-worktrees (git state) by cleaning the team registry itself.
triggers:
  - "/squadkit:clean-stale-teams"
  - "clean up stale squads"
  - "delete stale team"
  - "remove squad remnants"
  - "prune ~/.claude/teams"
allowed-tools: Bash, Read, TeamDelete, AskUserQuestion
---

# Squadkit Clean Stale Teams

Remove orphaned team registries left under `~/.claude/teams/<name>/`. Each entry is a `config.json` describing a squad's lead and members. When a session ends without tearing its squad down — or a SessionStart hook flags remnants — the dir lingers and the auto-mode classifier later flags ad-hoc `rm` of it as unscoped destruction. This skill makes the prune legible: classify, show, then delete.

## Input

`$ARGUMENTS` — optional. A specific team name to target (e.g. `session-604893df`). When omitted, scan and classify every dir under `~/.claude/teams/`.

## Process

### 1. Enumerate team dirs

List `~/.claude/teams/`. For each subdir, Read its `config.json`. If the dir has no `config.json`, treat it as malformed-but-removable and note it.

### 2. Classify each team

For every team, derive a verdict from its config and live state:

- **Members** — count entries in `members[]` whose `backendType` is not `in-process`. A team with only the in-process lead has zero real members.
- **Current session** — compare `leadSessionId` against the running session id. Never remove the team for the *current* live session unless the user explicitly named it (e.g. a SessionStart hook asked to tear it down).
- **Worktrees** — run `git worktree list` in the lead's `cwd` and check `.claude/worktrees/` there. A team referencing a live worktree is **not** safe to auto-remove.

A team is **safe to prune** when: only an in-process lead, zero spawned members, and no live worktree references.

### 3. Present the verdict

Show a compact table: team name, lead session, member count, worktree refs, and verdict (`prune` / `keep` / `needs confirmation`). For anything ambiguous (real members present, or it's the current session), use AskUserQuestion before touching it — never batch a risky delete into a safe sweep.

### 4. Remove the orphans

For each `prune` team:

- Prefer `TeamDelete` when the team is still registered with the running harness.
- Otherwise `rm -rf ~/.claude/teams/<name>` for a dead-session dir the harness no longer tracks.

Echo each removal. If the classifier blocks a delete the user already authorized, retry once so the user gets an approval prompt — do not silently skip it.

### 5. Report

List what was removed and what was kept (with the reason). Note whether `~/.claude/teams/` is now empty of session remnants.

## Constraints

- **Never remove a team with real (non-in-process) members** without explicit user confirmation — those may be live agents.
- **Never remove the current session's team** unless the user (or a SessionStart hook) explicitly named it for teardown.
- **Never delete a team whose lead `cwd` has a live worktree** referencing it; clean the worktree first (`swarmkit:clean-worktrees`).
- **Always show the verdict before deleting.** No silent sweeps.
- **One concern per delete.** Do not fold a risky removal into a batch of safe ones.
