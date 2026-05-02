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

Polish the rough edges across a scope you specify — a path, glob, or cross-cutting concern — in an isolated worktree, and open one PR. Single pass, single agent, single PR.

Lightweight sibling to polishkit's other skills:

- `polishkit:appraise` — score code quality without changing anything.
- `polishkit:sweep` — remove dead code and accumulated cruft (unused exports/imports/variables, stale files, build artifacts).
- `polishkit:polish` (this skill) — apply semantic code-quality fixes (reuse, quality, efficiency) across a scope.

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
- `--base <branch>` — override the resolved PR base branch (see Process step 3). When set, short-circuits config / `develop` / repo-default resolution.
- `--dry-run` — review and report findings without applying fixes; useful as a pre-flight before committing to a PR

If `<scope>` is empty:

> What scope should I polish? (path, glob, or cross-cutting concern + scope hint)

## Process

### 1. Resolve scope

For a path/glob, list files that match. For a cross-cutting concern, treat the description as the agent's *theme* and the path/glob hint as the *file boundary* — pass both to the agent.

Confirm at least one matching file exists. Pass the resolved file list to the agent verbatim so it doesn't re-discover scope.

Derive a kebab-case slug from the scope. Examples:
- `src/hooks/` → `hooks`
- `src/services/spotify/auth.ts` → `services-spotify-auth`
- `error handling in src/providers/` → `providers-error-handling`
- `naming consistency in hooks` → `hooks-naming`

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

The agent's branch must be cut from the project's PR base, and `gh pr create` must explicitly target the same branch (otherwise it falls through to the GitHub default — usually `main` — which silently produces wrong-base PRs against repos that develop on a non-default branch).

Polishkit resolves the base standalone — no other plugin is required. If flowkit is also installed and has set its own per-session base, polishkit silently honors it as a courtesy, but never depends on it.

Resolve `BASE` in this order:

```bash
# 1. Explicit caller arg
BASE=""
if echo "$ARGUMENTS" | grep -qE '(^|[[:space:]])\-\-base[= ]'; then
  BASE=$(echo "$ARGUMENTS" | grep -oE '(^|[[:space:]])\-\-base[= ][^ ]+' | head -1 | sed 's/.*--base[= ]//')
fi

# 2. Polishkit's own config
if [ -z "$BASE" ]; then
  BASE=$(git config claude.polishkit.prBase 2>/dev/null)
fi

# 3. Optional flowkit interop — honored if flowkit set it, but not required
if [ -z "$BASE" ]; then
  BASE=$(git config claude.flowkit.prBase 2>/dev/null)
fi

# 4. develop if it exists on the remote
if [ -z "$BASE" ]; then
  if git ls-remote --heads origin develop | grep -q 'refs/heads/develop'; then
    BASE="develop"
  fi
fi

# 5. Fallback — use the repo default and warn
if [ -z "$BASE" ]; then
  REPO_DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")
  echo "warning: no base branch configured and 'develop' not found on remote; falling back to repo default ($REPO_DEFAULT)" >&2
  BASE="$REPO_DEFAULT"
fi
```

Pass the resolved `BASE` to the agent prompt as `BASE_BRANCH`. The agent must use it for both the branch cut **and** the `gh pr create --base` argument.

To pin a base for the current repo, run `git config claude.polishkit.prBase <branch>` (e.g. `develop`). The flowkit read at step 3 is best-effort interop only — polishkit works without flowkit installed.

### 4. Dispatch the subagent

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

1. Branch from `BASE_BRANCH` (provided by the orchestrator — never re-derive):
   ```
   git fetch origin "$BASE_BRANCH"
   git checkout -B polish/<slug> "origin/$BASE_BRANCH"
   [[ "$PWD" != *"worktrees"* ]] && echo "ERROR: not in worktree" && exit 1
   ```
2. First pass: read every file in scope and build a findings list grouped by category (reuse / quality / efficiency / deferred). Apply the cross-cutting theme filter if one was given.
3. Apply edits. Surgical changes; don't bundle unrelated fixes into a single "polish" commit. Group commits by category or by file (conventional-commit format).
4. Verify by running every command in `VERIFY_COMMANDS` (passed by the orchestrator). All MUST pass before push. If any fails, iterate until green or revert the breaking edit and list it as deferred.
5. Push and open the PR with `--base "$BASE_BRANCH"` explicitly (see PR BODY SHAPE below). **Never** call `gh pr create` without `--base` — without it, gh falls through to the GitHub default branch (often `main`), which silently produces wrong-base PRs.
6. Report the PR URL. That is the only acceptable termination condition.

**PR BODY SHAPE** — follow the canonical spec at `plugins/_shared/pr-body.md` (`## Summary` / `## Changes` / `## Test plan` plus issue-reference footer). Append one extra section after `## Test plan`:

```
## Findings deferred to issues
<list of fixes intentionally not applied (cap exceeded, behavior change, theme mismatch) with file:line refs>
```

The `## Test plan` checklist must include each command from `VERIFY_COMMANDS` as a `- [ ]` item.

**NO-OP IS LEGITIMATE** — if the pass finds nothing actionable in the scope, open the PR anyway with `## Summary` stating `no actionable simplifications found` and a `## Findings deferred to issues` section listing what was considered. Manufactured churn is worse than a no-op PR.

### 5. Dry-run mode

If `--dry-run` is set, the agent skips the apply/commit/push phase and instead returns a structured findings report inline (not as a PR). Useful as a pre-flight before committing to a full pass.

### 6. Report

Print one line confirming dispatch (scope, slug, branch, base branch, agent type, model, max-files, verify commands). Don't wait synchronously — the harness notifies on completion. When notified:

- Verify branch is pushed: `git ls-remote --exit-code origin polish/<slug>`
- Verify the PR exists and targets the resolved base: `gh pr list --head polish/<slug> --json baseRefName,url`
- Report the PR URL.

## Constraints

- One agent per invocation, one PR per agent. Never fan out multiple polish agents on the same scope.
- Lightweight by default — if scope is so large the agent wants to touch >50 files, it should narrow to the highest-impact subset and defer the rest. The skill is for cross-cutting cleanup, not whole-codebase rewrites.
- Always pass relative paths to the agent. Never include absolute repo paths in the prompt.
- Always run in an isolated worktree. Never edit the scope directly from the orchestrator.
- Verify must be green before push. Red builds are never acceptable, even for "lightweight" passes.
- No-op PR is legitimate — never invent edits to justify the run.
- Defer behavior-changing fixes to follow-up issues; this skill is for safe, fast cleanup only.
