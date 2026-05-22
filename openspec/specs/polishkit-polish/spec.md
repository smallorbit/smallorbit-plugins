# Polish

## Purpose
Polish applies semantic code-quality fixes — reuse, quality, and efficiency — across a user-specified scope in an isolated worktree and opens one PR. It is a lightweight, single-pass, single-agent cleanup tool for targeted cross-cutting improvements that preserves public contracts and gates on a green build before pushing.

## Requirements

### Requirement: Scope intake
Polish SHALL accept a scope as a path, glob, or cross-cutting concern with a scope hint. For a path or glob, Polish SHALL enumerate matching files and pass them verbatim to the dispatched agent. For a cross-cutting concern, the description serves as the agent theme and the accompanying hint defines the file boundary. If no scope is provided, Polish SHALL prompt the user before proceeding.

#### Scenario: Path or glob scope provided
- **WHEN** the user provides a path or glob (e.g. `src/hooks/`)
- **THEN** Polish resolves all matching files and passes the explicit list to the agent

#### Scenario: Cross-cutting concern scope provided
- **WHEN** the user provides a natural-language concern with a scope hint (e.g. `error handling in src/providers/`)
- **THEN** Polish passes the concern description as the agent theme and the hint as the file boundary

#### Scenario: No scope provided
- **WHEN** the invocation includes no scope argument
- **THEN** Polish prompts the user for a scope before dispatching any agent

### Requirement: Verify command detection
Before dispatching, Polish SHALL detect the project's canonical typecheck and test commands. If no command is found, Polish SHALL ask the user before dispatching.

#### Scenario: Verify command found
- **WHEN** at least one canonical typecheck or test command is detectable in the project
- **THEN** Polish passes that command to the agent as the verify step

#### Scenario: No verify command detectable
- **WHEN** no verify command is found
- **THEN** Polish asks the user for the verify command before dispatching

### Requirement: PR base branch resolution
Polish SHALL resolve a base branch before dispatching, preferring explicit arguments over configuration over remote defaults. The resolved base MUST be used for both the branch cut and the `gh pr create --base` argument.

#### Scenario: Explicit --base overrides all
- **WHEN** `--base <branch>` is present in the arguments
- **THEN** that branch is used as the PR base, bypassing all other resolution

#### Scenario: No resolvable configured base
- **WHEN** no explicit arg, config key, or known remote branch resolves a base
- **THEN** the repository default branch is used and a warning is emitted

### Requirement: Isolated single-agent dispatch
Polish SHALL dispatch exactly one agent per invocation. Polish MUST run all fix work in an isolated worktree, in bypassPermissions mode, and in the background. Polish MUST NOT dispatch more than one agent per invocation.

#### Scenario: Agent dispatched
- **WHEN** Polish is invoked with a valid scope
- **THEN** exactly one agent runs in an isolated worktree and Polish returns without blocking on the agent's completion

### Requirement: Semantic fix application
Polish SHALL apply fixes across three categories: reuse (duplicated logic; inlined alternatives where an existing helper exists), quality (unclear naming, dead code, weak error handling, type hygiene gaps), and efficiency (quadratic loops where linear is possible, redundant async waits, unnecessary recomputations). When a cross-cutting theme is given, Polish SHALL prioritize only fixes matching that theme and defer all others to the PR's deferred findings section. Polish SHALL NOT change any public contract; such fixes MUST be deferred with a file:line reference.

#### Scenario: Theme-filtered pass
- **WHEN** a cross-cutting concern theme is provided
- **THEN** Polish applies only fixes relevant to that theme and lists all other findings as deferred

#### Scenario: Public contract preserved
- **WHEN** a fix would alter an exported or public API surface
- **THEN** Polish leaves the code unchanged and lists it in deferred findings with a file:line reference

### Requirement: File cap enforcement
Polish SHALL not touch more than the configured max-files limit (default: 15) in a single PR. If the actionable scope exceeds the cap, Polish SHALL fix the highest-impact subset and list the remainder as deferred findings.

#### Scenario: Scope exceeds cap
- **WHEN** the number of actionable files exceeds max-files
- **THEN** Polish fixes the highest-impact subset up to the cap and lists remaining files as deferred findings

### Requirement: Green-build gate
Polish SHALL run every command in VERIFY_COMMANDS before pushing. All commands MUST pass. If a command fails after an edit, Polish SHALL iterate to fix the failure or revert that specific edit and list it as deferred. A failing build MUST NOT be pushed.

#### Scenario: All verify commands pass
- **WHEN** all VERIFY_COMMANDS pass after edits are applied
- **THEN** Polish proceeds to push and open the PR

#### Scenario: Verify command fails after an edit
- **WHEN** a verify command fails following a specific edit
- **THEN** Polish either resolves the failure or reverts that edit and adds it to deferred findings before pushing

### Requirement: Single PR delivery
Polish SHALL open exactly one PR per invocation targeting the resolved base branch. The PR body MUST follow the canonical shape (## Summary / ## Changes / ## Test plan / ## Findings deferred to issues). The `gh pr create` call MUST include `--base <BASE_BRANCH>` explicitly. A no-op result — scope examined but no actionable fixes found — is valid; Polish SHALL open a PR in that case stating no actionable simplifications were found.

#### Scenario: Fixes applied and verified
- **WHEN** Polish applies at least one edit that passes all verify commands
- **THEN** exactly one PR is opened against the resolved base with a canonical body

#### Scenario: No actionable fixes found
- **WHEN** Polish finds nothing to change in the scope
- **THEN** one PR is still opened with "no actionable simplifications found" in ## Summary

### Requirement: Dry-run mode
When `--dry-run` is provided, Polish SHALL report findings inline without applying any edits, committing, pushing, or opening a PR.

#### Scenario: Dry-run invocation
- **WHEN** `--dry-run` is present in the arguments
- **THEN** Polish produces a structured findings report in the conversation and makes no file changes
