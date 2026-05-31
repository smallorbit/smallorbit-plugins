# Migrate v4

## Purpose

Migrate a repository from the legacy flowkit v3 layout (a `develop` → release-candidate → `main` split with rebase-merge ceremony) to flowkit v4 (single-trunk GitHub Flow on `main`, no release-candidate stage). The skill is an interactive, one-time helper that detects legacy state, presents the full plan up front, executes each destructive step under operator confirmation, and is idempotent on already-migrated repositories.

## Requirements

### Requirement: No-argument invocation

The skill SHALL accept no arguments and SHALL derive all decisions from the live repository and the GitHub remote.

#### Scenario: Invoked without arguments

- **WHEN** the skill is invoked
- **THEN** it inspects the local repository and the GitHub remote to determine state, taking no input parameters

### Requirement: Legacy state detection

The skill SHALL detect the repository's current shape with read-only commands that mutate nothing, and SHALL classify the repository as legacy when any of the following hold: the GitHub default branch is `develop`; `develop` exists on origin while `main` does not; the `claude.flowkit.defaultBranchPrompted` config key is non-empty; or one or more release-candidate branches exist on origin.

#### Scenario: Detection commands are non-mutating

- **WHEN** the skill reads the GitHub default branch, origin branches, and legacy config keys
- **THEN** no branch, tag, config, or remote state is changed during detection

#### Scenario: Default branch is develop

- **WHEN** the GitHub default branch is `develop`
- **THEN** the repository is classified as legacy

#### Scenario: develop present but main absent

- **WHEN** `develop` exists on origin and `main` does not
- **THEN** the repository is classified as legacy

#### Scenario: Legacy default-branch-prompted marker present

- **WHEN** the `claude.flowkit.defaultBranchPrompted` config key is non-empty
- **THEN** the repository is classified as legacy

#### Scenario: Release-candidate branches present

- **WHEN** one or more `rc/*` branches exist on origin
- **THEN** the repository is classified as legacy

#### Scenario: Stale pin detected

- **WHEN** `claude.flowkit.prBase` is set but its target branch resolves neither locally nor on origin
- **THEN** the pin is recorded as stale for later surfacing during config cleanup

### Requirement: Plan shown before any mutation

The skill SHALL assemble and display an ordered migration plan — listing the steps that will run plus the informational items the operator must handle manually — before performing any mutation. It SHALL NOT use a decide-as-you-go flow.

#### Scenario: Plan lists detected state and ordered steps

- **WHEN** the repository is classified as legacy
- **THEN** the skill prints the detected state, the ordered list of steps that will run, and an informational list of release-candidate and feature branches that will not be auto-deleted

#### Scenario: No mutation precedes the plan

- **WHEN** the skill begins execution
- **THEN** no repository state is changed before the full plan has been displayed

### Requirement: Up-front plan confirmation

The skill SHALL ask the operator to confirm the plan once, before any mutation. If the operator answers anything other than affirmative, the skill SHALL abort cleanly without touching the repository.

#### Scenario: Operator confirms the plan

- **WHEN** the operator answers yes to the plan confirmation
- **THEN** the skill proceeds to per-step execution

#### Scenario: Operator declines the plan

- **WHEN** the operator answers anything other than yes
- **THEN** the skill aborts without mutating the repository

### Requirement: Per-step confirmation with skip and abort

Each destructive step SHALL prompt the operator independently, offering run, skip, and abort choices. Skipping a step SHALL NOT skip subsequent steps; aborting SHALL stop execution immediately.

#### Scenario: Operator runs a step

- **WHEN** the operator answers yes to a step prompt
- **THEN** that step's mutation is performed

#### Scenario: Operator skips a step

- **WHEN** the operator answers skip to a step prompt
- **THEN** that step is not performed and the skill continues to the next step

#### Scenario: Operator aborts at a step

- **WHEN** the operator answers abort to a step prompt
- **THEN** execution stops immediately and no further steps run

### Requirement: Ensure local main exists

The skill SHALL fetch from origin and ensure a local `main` branch exists before fast-forwarding. When local `main` is absent, it SHALL create `main` from `origin/main` if that exists, otherwise from `origin/develop` so a subsequent fast-forward has a base. This step is always-safe and needs no prompt beyond the plan-level confirmation.

#### Scenario: Local main created from origin/main

- **WHEN** local `main` does not exist and `origin/main` exists
- **THEN** local `main` is created from `origin/main`

#### Scenario: Local main created from origin/develop

- **WHEN** local `main` does not exist and `origin/main` does not exist
- **THEN** local `main` is created from `origin/develop`

### Requirement: Fast-forward main to develop

The skill SHALL fast-forward `main` to the tip of `develop`. It SHALL NOT auto-merge when a fast-forward is not possible; instead it SHALL surface the divergence and ask the operator how to proceed.

#### Scenario: Clean fast-forward

- **WHEN** `main` can be fast-forwarded to `develop`
- **THEN** `main` is advanced to `develop`'s tip and the result is reported

#### Scenario: Divergence blocks fast-forward

- **WHEN** `main` and `develop` have diverged so a fast-forward is impossible
- **THEN** the skill reports the divergence and the commit ranges and asks the operator how to proceed rather than auto-merging

### Requirement: Push main to origin

The skill SHALL push `main` to origin under operator confirmation.

#### Scenario: Operator confirms pushing main

- **WHEN** the operator confirms the push-main step
- **THEN** `main` is pushed to origin

### Requirement: Switch GitHub default branch to main

The skill SHALL switch the GitHub default branch from `develop` to `main` under operator confirmation, warning that the change is destructive and that open PRs targeting `develop` will need to be retargeted manually.

#### Scenario: Operator confirms the default-branch switch

- **WHEN** the operator confirms the switch step
- **THEN** the GitHub default branch is set to `main`

### Requirement: Delete develop branches

The skill SHALL delete `origin/develop` under operator confirmation, and SHALL delete the local `develop` branch under operator confirmation only when it exists locally.

#### Scenario: Operator confirms deleting origin/develop

- **WHEN** the operator confirms the delete-origin-develop step
- **THEN** `develop` is deleted on origin

#### Scenario: Local develop deleted only when present

- **WHEN** the operator confirms the delete-local-develop step and a local `develop` branch exists
- **THEN** the local `develop` branch is deleted

#### Scenario: Local develop absent is a no-op

- **WHEN** no local `develop` branch exists
- **THEN** the delete-local-develop step makes no change

### Requirement: Legacy config cleanup

The skill SHALL unset `claude.flowkit.defaultBranchPrompted` under operator confirmation, but only when it is currently set. It SHALL auto-unset `claude.flowkit.prBase` only when that key's target branch no longer exists and only after operator confirmation; it SHALL NOT unset a `prBase` that still resolves to a real branch.

#### Scenario: defaultBranchPrompted unset when set

- **WHEN** `claude.flowkit.defaultBranchPrompted` is set and the operator confirms
- **THEN** the key is unset

#### Scenario: Stale prBase surfaced and unset on confirmation

- **WHEN** `claude.flowkit.prBase` points at a branch that no longer exists and the operator confirms
- **THEN** the key is unset

#### Scenario: Live prBase never auto-unset

- **WHEN** `claude.flowkit.prBase` resolves to a real branch
- **THEN** it is left untouched

### Requirement: Surface but never auto-delete RC and feature branches

The skill SHALL report release-candidate and feature branches as informational items and SHALL NOT auto-delete them. Feature branches SHALL NEVER be auto-deleted because they may hold unfinished work; release-candidate branches are surfaced for the operator to delete per-branch after verification.

#### Scenario: Release-candidate branches surfaced

- **WHEN** `rc/*` branches exist
- **THEN** they are listed with guidance to delete them manually once verified, and none are deleted by the skill

#### Scenario: Feature branches surfaced

- **WHEN** `feature/*` branches exist
- **THEN** they are listed with a warning that they may contain unfinished work, and none are deleted by the skill

### Requirement: Branch-protection rules left untouched

The skill SHALL NOT modify branch-protection rules; they are operator-owned policy. It MAY surface the existence of protection rules on `develop` as informational.

#### Scenario: Protection rules surfaced not modified

- **WHEN** branch-protection rules exist on `develop`
- **THEN** their existence is reported as informational and no protection rule is modified

### Requirement: Final report

The skill SHALL print a summary covering which steps ran, which were skipped, what remains for manual cleanup, and the repository's new state (default branch, `origin/main` HEAD, and absence of `develop`).

#### Scenario: Summary printed after execution

- **WHEN** execution completes
- **THEN** a summary reports steps run, steps skipped, remaining manual cleanup, and the new repository state

### Requirement: Idempotent on migrated repositories

The skill MUST be idempotent: when detection finds no legacy artifacts, it SHALL report that there is nothing to do and exit zero without any mutation.

#### Scenario: Already-migrated repository is a no-op

- **WHEN** detection finds no legacy artifacts
- **THEN** the skill reports that the repository is already on single-trunk `main` and exits zero without mutating anything
