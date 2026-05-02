# Polishkit

A Claude Code plugin for improving what you've already built. Assess code craft with a connoisseur's eye, sweep for accumulated cruft, eliminate dead code, and apply cross-cutting code-quality fixes — four focused skills for codebase quality.

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

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **critique** | `/critique` | Assesses code for elegance, architecture, and craft across 5 weighted dimensions. Produces a scored report with beauty highlights and violation flags. Works on single files, modules, or full repos. |
| **tidy-codebase** | `/tidy-codebase` | Codebase hygiene sweep — finds and cleans up stale files, outdated documentation, build artifacts, and accumulated cruft. Confirms each action before executing. |
| **dead-code** | `/dead-code` | Scans for unused exports, unreachable branches, dead variables, and obsolete imports. Runs language-appropriate static analysis, presents findings with file:line references, and removes after confirmation. |
| **buff** | `/buff <scope>` | Buffs out cross-cutting code-quality issues (reuse, quality, efficiency) across a path, glob, or themed scope. Runs in an isolated worktree, gates on your project's verify commands, and opens one PR. |

## Typical Workflows

### Assess code quality before a refactor

```
/critique src/services          # Score the service layer across 5 dimensions
```

### Clean up after a long sprint

```
/tidy-codebase                  # Full hygiene sweep — stale docs, artifacts, merged branches
/dead-code                      # Find and remove unused exports and imports
```

### Deep-clean a specific module

```
/dead-code src/components       # Scope dead-code scan to one directory
/critique src/components        # Then assess what remains
```

### Prepare for a code review

```
/critique                       # Get an honest assessment before submitting
```

### Apply cross-cutting cleanup as a single PR

```
/buff src/hooks/                        # Path scope
/buff error handling in src/providers/  # Cross-cutting theme + boundary
```

## How critique Works

`/critique` surveys the codebase structure, identifies the language(s) in use, and scores across five weighted dimensions: Architecture & Separation of Concerns (30%), Naming & Readability (25%), Algorithmic Elegance (20%), Testability & Test Design (15%), and Idiomatic Consistency (10%). It always leads with beauty highlights before discussing flaws, and flags critical violations (god classes, magic numbers, functions over 30 lines) in a dedicated section.

## How tidy-codebase Works

`/tidy-codebase` runs parallel checks for stale docs, build artifacts, documentation gaps, duplicate content, and git hygiene issues (merged branches, stale worktrees, orphaned remotes). Findings are organized into Remove / Update / Keep categories and confirmed via `AskUserQuestion` before any changes are made.

## How dead-code Works

`/dead-code` detects the project language and available static analysis tools, then runs all applicable checks in parallel: unused exports, unused imports, dead variables, and commented-out code blocks. Findings are grouped by severity, shown with file:line references, and confirmed in batches before removal. After cleanup, it verifies the codebase still compiles.

## How buff Works

`/buff` takes a scope (path, glob, or cross-cutting concern + scope hint), resolves the file list, sniffs the project's typecheck/test commands, and dispatches a single subagent in an isolated worktree. The agent applies semantic fixes across three categories — reuse (extract duplication, use existing helpers), quality (naming, error handling, type hygiene), and efficiency (avoidable recomputation, quadratic loops) — under a soft cap on files touched. It must keep public surfaces compatible, gate on every verify command, and open one PR with deferred findings called out for follow-up.

## Pairing with Other Plugins

Polishkit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Polishkit improves quality; [speckit](../speckit) defines the next work; [swarmkit](../swarmkit) executes it:

```
/critique                       # Assess current quality
/spec address architecture gaps # Plan improvements as issues
/swarm                          # Execute with parallel agents
```
