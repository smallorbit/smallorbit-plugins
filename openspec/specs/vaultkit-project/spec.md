# Project

## Purpose
Project manages a `Projects/` second brain inside any Obsidian vault. It supports three operations — loading an existing project's context at the start of a session, initializing a new project from a template, and updating a project's files after work — while preserving Obsidian vault metadata conventions.

## Requirements

### Requirement: Obsidian dependency
Project SHALL invoke the `vaultkit:obsidian` skill first, since every operation depends on that skill's vault connection details and command reference.

#### Scenario: Operation begins
- **WHEN** any Project operation starts
- **THEN** Project invokes `vaultkit:obsidian` before performing vault commands

### Requirement: Vault parameter resolution
Every operation SHALL require a vault name supplied explicitly by the caller. If no vault name is given, Project SHALL list available vaults (via `obsidian vaults`) and ask the user which vault to use before continuing. To resolve the vault's filesystem path for `mkdir` and direct file edits, Project SHALL run `obsidian vault="<VAULT>" vault` and store the result for use in filesystem commands.

#### Scenario: Vault name provided
- **WHEN** the caller supplies a vault name
- **THEN** Project uses that vault and resolves its filesystem path via `obsidian vault="<VAULT>" vault`

#### Scenario: Vault name missing
- **WHEN** no vault name is supplied
- **THEN** Project lists the available vaults and asks the user which to use before continuing

### Requirement: Project folder convention
Project SHALL treat each project as living under `<vault>/Projects/<ProjectName>/`, with `Overview.md` as the project hub. Project folder names SHALL match what the user calls the project verbatim, with no slugifying. When unsure about a project's casing or spelling, Project SHALL check existing folders (e.g. `obsidian vault="<VAULT>" folders`) rather than guess.

#### Scenario: Project hub location
- **WHEN** Project references a project's primary content
- **THEN** it uses `<vault>/Projects/<ProjectName>/Overview.md` as the hub file

#### Scenario: Folder name maps verbatim
- **WHEN** a project name contains spaces or mixed case
- **THEN** the folder name matches the project name verbatim without slugifying

#### Scenario: Uncertain name casing
- **WHEN** Project is unsure of a project's casing or spelling
- **THEN** it lists existing project folders rather than guessing the name

### Requirement: Load project context
The load operation SHALL restore full project context before any session work. It SHALL confirm the project folder exists, read `Overview.md` first and any sibling files that exist (such as `Tasks.md`, `Ideas.md`, `Architecture.md`), then summarize the current status, active tasks, and any noted blockers to the user before proceeding.

#### Scenario: Existing project loaded
- **WHEN** load runs for a project folder that exists
- **THEN** Project reads `Overview.md` first, reads any existing sibling files, and summarizes status, active tasks, and blockers before proceeding with work

#### Scenario: Missing sibling files
- **WHEN** an optional sibling file such as `Tasks.md` does not exist
- **THEN** Project skips that file and continues loading from the files that do exist

### Requirement: Initialize a new project
The init operation SHALL create a project that does not yet exist from the template. It SHALL resolve the vault path, read the template at `Projects/_TEMPLATE_/Overview.md`, create the destination folder with `mkdir -p` (because the CLI `move` does not auto-create directories), and write a new `Overview.md` filling in the project name as the H1, a one-sentence description (asking the user if unknown), `started:` set to today, `status: active`, and any known goals or context.

#### Scenario: New project created from template
- **WHEN** init runs for a project that does not exist
- **THEN** Project reads the template, creates the destination folder with `mkdir -p`, and writes an `Overview.md` with the project name, description, today's `started:` date, and `status: active`

#### Scenario: Description unknown
- **WHEN** init has no description for the project
- **THEN** Project asks the user for a one-sentence description before writing `Overview.md`

### Requirement: Projects Index maintenance
On init, Project SHALL add a row for the new project to the Projects Index table in `_README.md`, formatted as a wikilink to the project's `Overview` with its status and date. This edit SHALL be made with birth-time preservation via the `vaultkit:file-edit` sub-skill. The Projects Index in `_README.md` SHALL be kept current as the master list.

#### Scenario: Index row added on init
- **WHEN** init finishes creating a project
- **THEN** Project adds an Index row to `_README.md` linking the project's `Overview` with its status and date, edited via `vaultkit:file-edit`

### Requirement: Update project files
The update operation SHALL append to or modify the relevant project files after work, decisions, or status changes. Status or phase changes go to the `Overview.md` Status section; task changes to the Tasks section (or `Tasks.md` if split); design decisions to the Architecture section (or `Architecture.md` if split); ideas to the Ideas section (or `Ideas.md` if split); blockers to Status > Blockers. Project SHALL read a file before editing it, and SHALL also update `Last updated:` in `Overview.md` whenever any project file is edited.

#### Scenario: Status change
- **WHEN** update records a project phase or overall status change
- **THEN** Project updates the Status section of `Overview.md`

#### Scenario: Task change
- **WHEN** update records a completed or new task
- **THEN** Project updates the Tasks section of `Overview.md`, or `Tasks.md` if that section is split out

#### Scenario: Last-updated stamp
- **WHEN** update edits any project file
- **THEN** Project also updates `Last updated:` in `Overview.md`

#### Scenario: Read before edit
- **WHEN** update is about to modify a file
- **THEN** Project reads the file first before editing it

### Requirement: Section splitting
When a section grows beyond roughly 30 lines or becomes hard to navigate, Project SHALL split it into its own file (`Tasks.md`, `Ideas.md`, or `Architecture.md`), then remove the section from `Overview.md` and replace it with a wikilink such as `See [[Tasks]]`.

#### Scenario: Oversized section split
- **WHEN** a section in `Overview.md` grows beyond roughly 30 lines
- **THEN** Project moves it to its own file, removes it from `Overview.md`, and leaves a wikilink to the new file

### Requirement: Folder creation before move
Because the Obsidian CLI `move` command does not auto-create missing destination directories, Project SHALL create a destination folder with `mkdir -p` before moving files into it.

#### Scenario: Moving into a new folder
- **WHEN** Project needs to move files into a folder that does not exist
- **THEN** it creates the folder with `mkdir -p` before running the `move` command

### Requirement: Birth-time-preserving edits
When editing an existing vault file, Project SHALL follow the `vaultkit:file-edit` sub-skill to preserve the file's birth time. For new files created with the Write tool, Project SHALL follow that sub-skill's new-file guidance to stamp the birth time.

#### Scenario: Editing an existing vault file
- **WHEN** update modifies an existing vault file
- **THEN** Project performs the edit via `vaultkit:file-edit` to preserve birth time

#### Scenario: Creating a new vault file
- **WHEN** Project writes a new vault file
- **THEN** it follows the `vaultkit:file-edit` new-file guidance to stamp the birth time

### Requirement: Frontmatter and status values
Project SHALL maintain `Overview.md` frontmatter with `tags: [project]`, a `status` field, and a `started:` date. The `status` value SHALL be one of `active` (currently being worked on), `on-hold` (paused, not abandoned), or `done` (completed).

#### Scenario: Status value used
- **WHEN** Project records or updates a project's status
- **THEN** the value is one of `active`, `on-hold`, or `done`

### Requirement: Concise, recall-oriented notes
Project SHALL keep updates concise — these are notes for recall, not documentation. Project SHALL always load context before starting work and never assume remembered project state.

#### Scenario: Starting work
- **WHEN** Project begins work on a project
- **THEN** it loads the project context first rather than assuming remembered state
