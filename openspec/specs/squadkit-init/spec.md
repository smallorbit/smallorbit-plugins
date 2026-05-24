# squadkit-init

## Purpose

Initialize squadkit in a repository by interviewing the operator for the four commands every downstream squadkit skill (role contracts, spawn-team, retro) reads, then persisting them to `.squadkit/config.json` at the main repo root. No per-stack presets and no auto-detection — every command comes from the operator verbatim, keeping the wizard stack-agnostic.

## Requirements

### Requirement: Main Repo Root Resolution
The system SHALL resolve the main repository root via `git rev-parse --git-common-dir` and write the config beneath it, never inside a linked worktree.

#### Scenario: Worktree caller writes to main root
- **WHEN** the wizard runs from inside a linked worktree where `.git` is a file pointer
- **THEN** the config path is computed from the shared `.git` directory so the file lands at the main repo root

#### Scenario: Non-repo invocation aborts
- **WHEN** the wizard runs outside any git repository
- **THEN** the command exits with a non-zero status and an error explaining the working directory is not a git repo

### Requirement: Overwrite Confirmation
The system SHALL refuse to overwrite an existing `.squadkit/config.json` without explicit operator confirmation via `AskUserQuestion`.

#### Scenario: Existing config triggers confirmation
- **WHEN** `.squadkit/config.json` already exists at the resolved path
- **THEN** its current contents are surfaced to the operator and an `Overwrite` / `Cancel` question is asked before the interview begins

#### Scenario: Cancel preserves existing config
- **WHEN** the operator answers `Cancel`
- **THEN** the skill exits with a one-line message naming the existing file and makes no changes

### Requirement: Interview-Only Input
The system SHALL collect every config value through interactive questions and SHALL NOT apply per-stack presets, auto-detect package managers, or infer commands from project files.

#### Scenario: Five sequential questions
- **WHEN** the interview runs
- **THEN** the operator is asked, in order, for `verify.typecheck`, `verify.test`, `verify.lint`, `install`, and `baseBranch`, with the running config surfaced after each answer

#### Scenario: Whitespace trimmed
- **WHEN** an answer contains leading or trailing whitespace
- **THEN** the trimmed value is stored

### Requirement: Optional and Empty Fields
The system SHALL accept empty answers for `verify.typecheck`, `verify.test`, and `install` as "no such step", and SHALL omit `verify.lint` entirely from the written JSON when the operator leaves it blank.

#### Scenario: Empty verify or install step persisted as empty string
- **WHEN** the operator leaves `verify.typecheck`, `verify.test`, or `install` blank
- **THEN** the field is written as an empty string so downstream skills treat it as "skip this step"

#### Scenario: Blank lint key omitted
- **WHEN** the operator leaves `verify.lint` blank
- **THEN** the `lint` key is omitted from the written JSON entirely so downstream roles can detect its absence

### Requirement: Default Base Branch
The system SHALL default `baseBranch` to `develop` when the operator accepts the default and SHALL NOT validate the value against the remote.

#### Scenario: Default accepted
- **WHEN** the operator accepts the default for question 5
- **THEN** `develop` is written as `baseBranch`

#### Scenario: Custom value accepted verbatim
- **WHEN** the operator supplies a non-default branch name
- **THEN** the value is written without remote validation

### Requirement: Config File Format
The system SHALL write the config as pretty-printed JSON with two-space indentation and a trailing newline at `<repo-root>/.squadkit/config.json`, creating the `.squadkit` directory if absent.

#### Scenario: Directory created when missing
- **WHEN** `.squadkit/` does not yet exist at the repo root
- **THEN** the directory is created before the file is written

#### Scenario: JSON shape
- **WHEN** the file is written
- **THEN** it contains a top-level object with `verify` (an object with `typecheck`, `test`, and optionally `lint`), `install`, and `baseBranch` and no other keys

### Requirement: Confirmation Output
The system SHALL emit the absolute path written, the full JSON contents, and a one-line next step pointing the operator to manual edits or rerunning the wizard.

#### Scenario: Post-write summary
- **WHEN** the config has been written
- **THEN** the absolute path, the JSON body, and a next-step line referencing manual edits or rerunning `/squadkit:init` are printed
