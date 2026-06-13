---
name: polish
description: Polish cross-cutting code-quality issues (reuse, quality, efficiency) across a scope (path, glob, or themed concern) in an isolated worktree and open one PR. Lightweight, fast, single-pass — for cleanup like naming consistency, error handling patterns, or type hygiene across modules.
triggers:
  - "polish"
  - "polish scope"
  - "polish across"
  - "polish the X concern"
  - "lightweight cleanup"
  - "cross-cutting cleanup"
---

# Polish

Polish the rough edges across a scope you specify — a path, glob, or cross-cutting concern — in an isolated worktree, and open one PR. Single pass, single agent, single PR. Use this when you want quick, targeted cleanup applied across a cross-cutting concern, not a full assessment or hygiene sweep.

## Input

`<scope>` — required. One of:

- **Path** — `src/hooks/`, `src/components/PlayerContent/`, `src/services/spotify/auth.ts`
- **Glob** — `src/**/use*.ts`, `src/components/**/*.test.tsx`
- **Cross-cutting concern** — a natural-language description plus a scope hint, e.g. `error handling in src/providers/`, `naming consistency in hooks`, `type hygiene across services/`

Optional flags:

- `--model <tier>` — `sonnet` (default) or `opus` for harder cross-cutting passes
- `--agent <type>` — subagent type override (default: `general-purpose`). The skill prompt embeds the review heuristics inline, so a dedicated `code-simplifier` agent is not required.
- `--max-files <N>` — soft cap on files the subagent should touch in one PR (default: 15). Lightweight stays lightweight.
- `--base <branch>` — override the resolved PR base branch (see Process step 3). When set, short-circuits the scoped-config-pin and `main` fallback resolution.
- `--dry-run` — review and report findings without applying fixes; useful as a pre-flight before committing to a PR

If `<scope>` is empty:

> What scope should I polish? (path, glob, or cross-cutting concern + scope hint)

## Process

### 1. Resolve scope

For a path/glob, list files that match. For a cross-cutting concern, treat the description as the agent's *theme* and the path/glob hint as the *file boundary* — pass both to the agent.

Confirm at least one matching file exists. Pass the resolved file list to the agent verbatim so it doesn't re-discover scope.

Derive a kebab-case slug from the scope. Examples:
- `src/hooks/` → `hooks`
- `error handling in src/providers/` → `providers-error-handling`

Branch name: `polish/<slug>`.

### 2. Detect the project's verify commands

Before dispatching the agent, sniff the repo for the canonical typecheck and test commands. The agent runs them as the green-build gate.

Detection order:

1. `CLAUDE.md` or `.claude/rules/*.md` — if a `## Verify` (or similar) section names commands, use those verbatim.
2. `package.json` `scripts` — prefer (in order) `typecheck`, `test:run`, `test`, `lint`. Skip watch-mode scripts.
3. `Makefile` targets — `make test`, `make check`.
4. Language defaults — `tsc --noEmit` (TS), `pytest` (Python), `go test ./...` (Go), `cargo test` (Rust).

If nothing matches, ask the user for the verify command before dispatching. Never invent a command the repo doesn't expose.

Pass the resolved verify commands to the agent prompt as `VERIFY_COMMANDS`.

### 3. Resolve the PR base branch

Implements the canonical chain at [`plugins/_shared/base-resolution.md`](../../../_shared/base-resolution.md), with polishkit's own config key `claude.polishkit.prBase` slotted at step 2 (before the optional `claude.flowkit.prBase` interop read at step 3). Polishkit works correctly without flowkit installed.

Pass the resolved `BASE` to the agent prompt as `BASE_BRANCH`. The agent must use it for both the branch cut **and** the `gh pr create --base` argument — calling `gh pr create` without `--base` falls through to the repo default branch and silently produces wrong-base PRs.

### 4. Dispatch the subagent

Spawn one agent with:

- `subagent_type`: `general-purpose` (overridable via `--agent`).
- `model`: `sonnet` (overridable via `--model`)
- `isolation`: `worktree`
- `mode`: `bypassPermissions`
- `run_in_background`: `true`

The agent prompt MUST include each section, in order:

**CONTEXT** — describe the scope in natural language, list every file in scope verbatim, and (if a cross-cutting concern was given) state the theme. CWD is the repo root of an isolated worktree; use relative paths only.

**TASK** — apply these review heuristics to the listed files:

1. **Reuse** — duplicated logic that should be extracted; existing helpers that should be used instead of inlined alternatives.
2. **Quality** — unclear naming, dead code, weak error handling, leaky abstractions, magic numbers, type hygiene gaps.
3. **Efficiency** — quadratic loops where linear is trivially possible, redundant async waits, unnecessary re-renders / recomputations.

For a cross-cutting theme, prioritize fixes matching that theme; deprioritize everything else (mention as deferred findings, don't fix).

**POLICY**:

- Keep public contracts compatible. Any fix that would change a public contract is left untouched and surfaced in the PR's `## Findings deferred to issues` section with file:line refs.
- Touch at most `--max-files` files (default 15). If the scope clearly exceeds the cap, fix the highest-impact subset and list the rest under deferred findings.
- A no-op pass is legitimate. If nothing actionable is found, open the PR anyway with `## Summary` stating `no actionable simplifications found` and a `## Findings deferred to issues` section listing what was considered. Manufactured churn is worse than a no-op PR.

**WORKFLOW**:

1. Branch from `BASE_BRANCH`:
   ```
   git fetch origin "$BASE_BRANCH"
   git checkout -B polish/<slug> "origin/$BASE_BRANCH"
   ```
2. First pass: read every file in scope and build a findings list grouped by category (reuse / quality / efficiency / deferred). Apply the cross-cutting theme filter if one was given.
3. Apply edits. Surgical changes; don't bundle unrelated fixes into a single commit. Group commits by category or by file (conventional-commit format).
4. Verify: run every command in `VERIFY_COMMANDS`. All MUST pass before push. If any fails, iterate until green or revert the breaking edit and list it as deferred.
5. Push and open the PR with `--base "$BASE_BRANCH"` explicitly. Report the PR URL.

**PR BODY SHAPE** — follow `plugins/_shared/pr-body.md` (`## Summary` / `## Changes` / `## Test plan` plus issue-reference footer). Append one extra section after `## Test plan`:

```
## Findings deferred to issues
<list of fixes intentionally not applied (cap exceeded, contract change, theme mismatch) with file:line refs>
```

The `## Test plan` checklist must include each command from `VERIFY_COMMANDS` as a `- [ ]` item.

### 5. Dry-run mode

If `--dry-run` is set, the agent skips the apply/commit/push phase and returns a structured findings report inline (not as a PR). Useful as a pre-flight before committing to a full pass.

### 6. Report

Print one line confirming dispatch (scope, slug, branch, base branch, agent type, model, max-files, verify commands). Don't wait synchronously — the harness notifies on completion. When notified, confirm via `gh pr list --head polish/<slug> --json baseRefName,url` that the PR exists and targets the resolved base, then report the URL.
