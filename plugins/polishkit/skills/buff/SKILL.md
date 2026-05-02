---
name: buff
description: Buff out cross-cutting code-quality issues (reuse, quality, efficiency) across a scope (path, glob, or themed concern) in an isolated worktree and open one PR. Lightweight, fast, single-pass — for cleanup like naming consistency, error handling patterns, or type hygiene across modules.
triggers:
  - "buff"
  - "buff scope"
  - "buff across"
  - "buff the X concern"
  - "lightweight polish"
  - "cross-cutting cleanup"
---

# Buff

Buff out the rough edges across a scope you specify — a path, glob, or cross-cutting concern — in an isolated worktree, and open one PR. Single pass, single agent, single PR.

Lightweight sibling to polishkit's other skills:

- `polishkit:critique` — score code quality without changing anything.
- `polishkit:dead-code` — remove unused exports/imports/variables.
- `polishkit:tidy-codebase` — sweep stale files and accumulated cruft.
- `polishkit:buff` (this skill) — apply semantic code-quality fixes (reuse, quality, efficiency) across a scope.

Use this when you want quick, targeted cleanup applied across a cross-cutting concern, not a full assessment or hygiene sweep.

## Input

`<scope>` — required. One of:

- **Path** — `src/hooks/`, `src/components/PlayerContent/`, `src/services/spotify/auth.ts`
- **Glob** — `src/**/use*.ts`, `src/components/**/*.test.tsx`
- **Cross-cutting concern** — a natural-language description plus a scope hint, e.g. `error handling in src/providers/`, `naming consistency in hooks`, `type hygiene across services/`

Optional flags:

- `--model <tier>` — `sonnet` (default) or `opus` for harder cross-cutting passes
- `--agent <type>` — subagent type override (default: `general-purpose`). The skill prompt embeds the review heuristics inline, so a dedicated `code-simplifier` agent is not required.
- `--max-files <N>` — soft cap on files the subagent should touch in one PR (default: 15). Lightweight stays lightweight.
- `--dry-run` — review and report findings without applying fixes; useful as a pre-flight before committing to a PR

If `<scope>` is empty:

> What scope should I buff? (path, glob, or cross-cutting concern + scope hint)

## Process

### 1. Resolve scope

For a path/glob, list files that match. For a cross-cutting concern, treat the description as the agent's *theme* and the path/glob hint as the *file boundary* — pass both to the agent.

Confirm at least one matching file exists. Pass the resolved file list to the agent verbatim so it doesn't re-discover scope.

Derive a kebab-case slug from the scope. Examples:
- `src/hooks/` → `hooks`
- `src/services/spotify/auth.ts` → `services-spotify-auth`
- `error handling in src/providers/` → `providers-error-handling`
- `naming consistency in hooks` → `hooks-naming`

Branch name: `buff/<slug>`.

### 2. Detect the project's verify commands

Before dispatching the agent, sniff the repo for the canonical typecheck and test commands. The agent runs them as the green-build gate.

Detection order:

1. `CLAUDE.md` or `.claude/rules/*.md` — if a `## Verify` (or similar) section names commands, use those verbatim.
2. `package.json` `scripts` — prefer (in order) `typecheck`, `test:run`, `test`, `lint`. Skip watch-mode scripts.
3. `Makefile` targets — `make test`, `make check`.
4. Language defaults — `tsc --noEmit` (TS), `pytest` (Python), `go test ./...` (Go), `cargo test` (Rust).

If nothing matches, ask the user for the verify command before dispatching. Never invent a command the repo doesn't expose.

Pass the resolved verify commands to the agent prompt as `VERIFY_COMMANDS`.

### 3. Dispatch the subagent

Spawn one agent with:

- `subagent_type`: `general-purpose` (overridable via `--agent`).
- `model`: `sonnet` (overridable via `--model`)
- `isolation`: `worktree`
- `mode`: `bypassPermissions`
- `run_in_background`: `true`

The agent prompt MUST include each section, in order:

**CONTEXT** — describe the scope in natural language, list every file in scope verbatim, and (if a cross-cutting concern was given) state the theme. Note CWD is the repo root of an isolated worktree and the agent must use **relative paths only**.

**TASK** — apply these review heuristics to the listed files:

1. **Reuse** — duplicated logic that should be extracted; existing helpers that should be used instead of inlined alternatives.
2. **Quality** — unclear naming, dead code, weak error handling, leaky abstractions, magic numbers, type hygiene gaps.
3. **Efficiency** — quadratic loops where linear is trivially possible, redundant async waits, unnecessary re-renders / recomputations in hooks (apply `react-useeffect` heuristics where applicable).

For a cross-cutting theme, prioritize fixes matching that theme; deprioritize everything else (mention as deferred findings, don't fix).

**RESPECT BEHAVIOR** — keep public surfaces compatible. If a fix would change a public contract, leave it untouched and surface in the PR's `## Findings deferred to issues` section with file:line refs.

**CONSTRAINTS** — read `CLAUDE.md` and `.claude/rules/` before editing. Honor every hard contract found there. No new dependencies. No type-error suppression (e.g. `as any`, `@ts-ignore`, `# type: ignore` without justification). Follow the project's commit message and authorship conventions.

**SOFT CAP** — touch at most `--max-files` files (default 15). If the scope clearly exceeds the cap, fix the highest-impact subset and list the rest under deferred findings. Lightweight passes stay lightweight.

**WORKFLOW**:

1. Branch from the repo's base branch (`develop` if it exists, otherwise `main`):
   ```
   BASE=$(git ls-remote --exit-code --heads origin develop >/dev/null 2>&1 && echo develop || echo main)
   git fetch origin "$BASE"
   git checkout -B buff/<slug> "origin/$BASE"
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: not in worktree" && exit 1
   ```
2. First pass: read every file in scope and build a findings list grouped by category (reuse / quality / efficiency / deferred). Apply the cross-cutting theme filter if one was given.
3. Apply edits. Surgical changes; don't bundle unrelated fixes into a single "buff" commit. Group commits by category or by file (conventional-commit format).
4. Verify by running every command in `VERIFY_COMMANDS` (passed by the orchestrator). All MUST pass before push. If any fails, iterate until green or revert the breaking edit and list it as deferred.
5. Push and open the PR (see PR BODY SHAPE below).
6. Report the PR URL. That is the only acceptable termination condition.

**PR BODY SHAPE** — follow the canonical spec at `plugins/_shared/pr-body.md` (`## Summary` / `## Changes` / `## Test plan` plus issue-reference footer). Append one extra section after `## Test plan`:

```
## Findings deferred to issues
<list of fixes intentionally not applied (cap exceeded, behavior change, theme mismatch) with file:line refs>
```

The `## Test plan` checklist must include each command from `VERIFY_COMMANDS` as a `- [ ]` item.

**NO-OP IS LEGITIMATE** — if the pass finds nothing actionable in the scope, open the PR anyway with `## Summary` stating `no actionable simplifications found` and a `## Findings deferred to issues` section listing what was considered. Manufactured churn is worse than a no-op PR.

### 4. Dry-run mode

If `--dry-run` is set, the agent skips the apply/commit/push phase and instead returns a structured findings report inline (not as a PR). Useful as a pre-flight before committing to a full pass.

### 5. Report

Print one line confirming dispatch (scope, slug, branch, agent type, model, max-files, verify commands). Don't wait synchronously — the harness notifies on completion. When notified:

- Verify branch is pushed: `git ls-remote --exit-code origin buff/<slug>`
- Verify the PR exists: `gh pr list --head buff/<slug>`
- Report the PR URL.

## Constraints

- One agent per invocation, one PR per agent. Never fan out multiple buff agents on the same scope.
- Lightweight by default — if scope is so large the agent wants to touch >50 files, it should narrow to the highest-impact subset and defer the rest. The skill is for cross-cutting cleanup, not whole-codebase rewrites.
- Always pass relative paths to the agent. Never include absolute repo paths in the prompt.
- Always run in an isolated worktree. Never edit the scope directly from the orchestrator.
- Verify must be green before push. Red builds are never acceptable, even for "lightweight" passes.
- No-op PR is legitimate — never invent edits to justify the run.
- Defer behavior-changing fixes to follow-up issues; this skill is for safe, fast cleanup only.
