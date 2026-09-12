# Polishkit

A Claude Code plugin for improving what you've already built. Appraise code craft with a connoisseur's eye, sweep dead code and accumulated cruft in one pass, and apply cross-cutting code-quality fixes — three focused skills for codebase quality.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers the plan → execute → ship loop and where polishkit fits in.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install polishkit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/polishkit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `git` and an authenticated [GitHub CLI](https://cli.github.com) (`gh`) — `/polish` and `/sweep` use both to cut branches, open PRs, and inspect branch PR state. `/appraise` is read-only and needs neither.

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **appraise** | `/appraise` | Appraises code for elegance, architecture, and craft across 5 weighted dimensions. Produces a scored report with beauty highlights and violation flags. Works on single files, modules, or full repos. |
| **sweep** | `/sweep [scope]` | Sweeps the codebase in two phases: dead code (unused exports, imports, variables, unreachable branches) and cruft (stale docs, build artifacts, duplicate content, merged branches). Confirms each action before executing, then commits and opens one PR. |
| **polish** | `/polish <scope>` | Polishes cross-cutting code-quality issues (reuse, quality, efficiency) across a path, glob, or themed scope. Runs in an isolated worktree, gates on your project's verify commands, and opens one PR (unless `--dry-run`, which reports findings inline and opens nothing). |

## Typical Workflows

### Appraise code quality before a refactor

```
/appraise src/services          # Score the service layer across 5 dimensions
```

### Clean up after a long sprint

```
/sweep                          # Full sweep — dead code + stale files in one pass
/sweep git-only                 # Just git hygiene — merged branches, stale worktrees, orphaned remotes
```

### Deep-clean a specific module

```
/sweep src/components           # Scope sweep to one directory
/appraise src/components        # Then assess what remains
```

### Prepare for a code review

```
/appraise                       # Get an honest assessment before submitting
```

### Apply cross-cutting cleanup as a single PR

```
/polish src/hooks/                        # Path scope
/polish error handling in src/providers/  # Cross-cutting theme + boundary
```

## How Appraise Works

`/appraise` surveys the codebase structure, identifies the language(s) in use, and scores across five weighted dimensions: Architecture & Separation of Concerns (30%), Naming & Readability (25%), Algorithmic Elegance (20%), Testability & Test Design (15%), and Idiomatic Consistency (10%). It always leads with beauty highlights before discussing flaws, and flags critical violations (god classes, magic numbers and strings, comments that restate the code, functions over ~30 lines, files over ~300 lines) in a dedicated Violations section.

## How Sweep Works

`/sweep` runs in two phases. **Phase 1 — dead code**: detects the project language and available static analysis tools (`tsc --noEmit`, `pyflakes`, `vulture`, `staticcheck`, etc.), then scans for unused exports, unused imports, dead variables, unreachable branches, and commented-out code blocks. **Phase 2 — cruft**: parallel checks for stale docs, build artifacts, documentation gaps, duplicate content, and git hygiene (merged branches, stale worktrees, orphaned remotes). Findings from both phases are merged into a single Remove / Update / Keep summary and confirmed via `AskUserQuestion` before any changes are made.

Scope is optional and takes three forms: a path or glob (restricts both phases to that subtree), a category hint — `dead-code-only` (Phase 1 only), `cruft-only` (Phase 2 only), or `git-only` (the git-hygiene subset of Phase 2) — or empty for a full sweep.

Sweep writes. After you approve, it applies the confirmed removals and edits, re-runs the project's verify command, commits `chore: sweep codebase`, and opens a PR targeting `claude.polishkit.prBase` if set, otherwise `main`. Remote branches are only ever proposed for deletion when their PR is MERGED — CLOSED-not-merged, OPEN, and no-PR branches are preserved.

## How Polish Works

`/polish` takes a scope (path, glob, or cross-cutting concern + scope hint), resolves the file list, sniffs the project's typecheck/test commands, and dispatches a single subagent in an isolated worktree. The agent applies semantic fixes across three categories — reuse (extract duplication, use existing helpers), quality (naming, error handling, type hygiene), and efficiency (avoidable recomputation, quadratic loops) — under a soft cap on files touched. It must keep public surfaces compatible, gate on every verify command, and open one PR with deferred findings called out for follow-up.

| Flag | Default | Effect |
|------|---------|--------|
| `--model <sonnet\|opus>` | `sonnet` | Model tier for the worker; `opus` for harder cross-cutting passes. |
| `--agent <type>` | `general-purpose` | Subagent type override. The review heuristics are embedded in the prompt, so no dedicated agent is required. |
| `--max-files <N>` | `15` | Soft cap on files the worker touches in one PR. |
| `--base <branch>` | resolved | Override the PR base branch. Otherwise resolved as `claude.polishkit.prBase` → `claude.flowkit.prBase` (courtesy interop) → `main`. |
| `--dry-run` | off | Review and report findings inline; skips apply/commit/push and opens no PR. |

## Pairing with Other Plugins

Polishkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Polishkit improves quality; [speckit](../speckit) defines the next work; [swarmkit](../swarmkit) executes it:

```
/appraise                       # Assess current quality
/spec address architecture gaps # Plan improvements as issues
/swarm                          # Execute with parallel agents
```
