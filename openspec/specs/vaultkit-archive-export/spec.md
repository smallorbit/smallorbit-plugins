# Archive Export

## Purpose
Archive Export picks up the latest conversation export produced by `/export session` in the current working directory and files it into the active Obsidian project's `Conversations/` folder. It writes two same-named copies — a plain-text `.txt` source of truth and an Obsidian-renderable `.md` that embeds the `.txt` and records the resumable session ID — then removes the source export.

## Requirements

### Requirement: Invocation Triggers
The skill SHALL activate when the user expresses intent to archive or file the latest conversation export. It SHOULD recognize phrasing such as "archive the export", "save the conversation", "file the export", or "archive this conversation", and is intended for use after the user has run `/export session` from the workspace root.

#### Scenario: Explicit archive phrasing
- **WHEN** the user says "archive the export", "save the conversation", "file the export", or "archive this conversation"
- **THEN** the skill activates and proceeds to file the latest export

### Requirement: Export File Convention
The skill SHALL expect the export to exist as `./session.txt` in the current working directory, produced by the user running `/export session` from that directory.

#### Scenario: Export present in working directory
- **WHEN** `./session.txt` exists in the current working directory
- **THEN** the skill treats it as the source export to archive

### Requirement: Source File Existence Check
The skill SHALL confirm that `./session.txt` exists before proceeding. When it is missing, the skill SHALL remind the user to run `/export session` from the current directory first rather than archiving anything.

#### Scenario: Source file present
- **WHEN** the skill checks for `./session.txt` and the file exists
- **THEN** the skill continues with the archive flow

#### Scenario: Source file missing
- **WHEN** the skill checks for `./session.txt` and the file does not exist
- **THEN** the skill reminds the user to run `/export session` from the current directory and does not archive anything

#### Scenario: Export run from the wrong directory
- **WHEN** `./session.txt` is not in the current directory because the user ran `/export` elsewhere
- **THEN** the skill MAY locate the file by searching for `session.txt` under the working tree to help recover it

### Requirement: Active Project Resolution
The skill SHALL determine the active Obsidian project to file the export under. It SHALL use conversation context when the active project is clear, and otherwise SHALL list the projects under the vault's `Projects` folder and ask the user which project to file the export under.

#### Scenario: Project clear from context
- **WHEN** the active project is evident from conversation context
- **THEN** the skill files the export under that project without prompting

#### Scenario: Project unclear
- **WHEN** the active project cannot be determined from context
- **THEN** the skill lists the projects under the vault's `Projects` folder and asks the user which project to file the export under

### Requirement: Session ID Resolution
The skill SHALL resolve the active session's UUID so the archive can record how to resume the conversation. It SHALL derive the session ID from the most recent per-session record associated with the current working directory.

#### Scenario: Session record present
- **WHEN** a per-session record exists for the current working directory
- **THEN** the skill resolves the session ID from the most recent such record

#### Scenario: Session record absent
- **WHEN** no per-session record can be found for the current working directory
- **THEN** the skill proceeds without a resolved session ID

### Requirement: Conversations Folder Provisioning
The skill SHALL ensure a `Conversations/` folder exists under the chosen project, creating it when it does not already exist, before writing any archive files.

#### Scenario: Conversations folder absent
- **WHEN** the chosen project has no `Conversations/` folder
- **THEN** the skill creates the `Conversations/` folder before writing files

#### Scenario: Conversations folder present
- **WHEN** the chosen project already has a `Conversations/` folder
- **THEN** the skill writes into the existing folder

### Requirement: Canonical Filename Format
The skill SHALL derive a single base name shared by both output files using the format `YYYY-MM-DD-HHMM-<slug>`, where the date and time are the current date and time (hours and minutes) and the slug is a 2–4 word hyphenated summary of the session topic. The two output files SHALL differ only by extension.

#### Scenario: Base name derived
- **WHEN** the skill prepares to write the archive
- **THEN** it derives a base name of the form `YYYY-MM-DD-HHMM-<slug>` from the current date/time and a hyphenated topic slug
- **AND** both output files share that base name, differing only by `.txt` versus `.md` extension

### Requirement: Plain-Text Copy
The skill SHALL write a `.txt` copy of `./session.txt` into the project's `Conversations/` folder under the canonical base name, and SHALL stamp the copied file's filesystem birth time following the `vaultkit:file-edit` new-file guidance.

#### Scenario: Plain-text copy written
- **WHEN** the source export is archived
- **THEN** the skill writes `<base>.txt` into the project's `Conversations/` folder as a copy of `./session.txt`
- **AND** the skill stamps that file's birth time per the `vaultkit:file-edit` new-file guidance

### Requirement: Obsidian Markdown Copy
The skill SHALL write a `.md` copy into the project's `Conversations/` folder under the same base name. The markdown file SHALL include the resumable session ID line, a resume command line, an Obsidian attachment embed of the `.txt` file, and the full conversation text inlined in a `plaintext` fenced code block for search indexing. The skill SHALL stamp the markdown file's birth time following the `vaultkit:file-edit` new-file guidance.

#### Scenario: Markdown copy written
- **WHEN** the source export is archived
- **THEN** the skill writes `<base>.md` into the project's `Conversations/` folder containing the session ID, a resume command, an attachment embed of `<base>.txt`, and the full conversation text in a `plaintext` fenced block
- **AND** the skill stamps that file's birth time per the `vaultkit:file-edit` new-file guidance

#### Scenario: Resume affordance recorded
- **WHEN** the markdown copy is written and a session ID was resolved
- **THEN** the markdown records how to resume the conversation using `claude --resume <session-id>`

### Requirement: Source Cleanup
After both archive copies have been written, the skill SHALL remove the source `./session.txt` from the working directory.

#### Scenario: Cleanup after archive
- **WHEN** both the `.txt` and `.md` copies have been written into the project's `Conversations/` folder
- **THEN** the skill removes the source `./session.txt`

### Requirement: Confirmation Report
After archiving, the skill SHALL report both destination paths and the session ID to the user.

#### Scenario: Successful archive
- **WHEN** the export has been archived into the project's `Conversations/` folder
- **THEN** the skill reports the destination paths of both the `.txt` and `.md` copies and the session ID
