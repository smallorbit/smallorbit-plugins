# Obsidian

## Purpose
Obsidian governs how to interact with Obsidian vaults on the user's behalf through the Obsidian CLI binary. It covers reading and discovery, full-text search, tag and property management, graph/link inspection, template access, daily notes, note writing (append, prepend, create, rename, move, delete), plugin management, and vault-maintenance workflows — while preserving each vault file's filesystem birth time so Obsidian's `created` metadata stays intact.

## Requirements

### Requirement: CLI access model
Obsidian SHALL perform all vault access through the Obsidian CLI binary, invoked as `obsidian vault=<VAULT> <command> [options]`. Obsidian MUST be running for CLI commands to work.

#### Scenario: Issuing a vault command
- **WHEN** any vault operation is performed
- **THEN** it is executed via the Obsidian CLI binary using the `obsidian vault=<VAULT> <command>` invocation form

### Requirement: Mandatory vault parameter
Every operation SHALL require an explicit vault name supplied by the caller. When no vault name is given, Obsidian SHALL list the available vaults (`obsidian vaults`), present them to the user, and ask which vault to use before continuing.

#### Scenario: Vault name supplied
- **WHEN** the caller supplies a vault name
- **THEN** Obsidian uses that vault for the operation

#### Scenario: Vault name missing
- **WHEN** no vault name is supplied
- **THEN** Obsidian lists the available vaults, presents them to the user, and asks which vault to use before continuing

### Requirement: Vault-not-found recovery
When a vault command returns "Vault not found", Obsidian SHALL list the available vaults, present them to the user, confirm the correct name, and flag any stale caller reference (such as memory files or hardcoded vault names in sub-skills) before retrying. Obsidian SHALL NOT silently retry with a guessed vault name.

#### Scenario: Vault not found
- **WHEN** a command returns "Vault not found"
- **THEN** Obsidian lists the available vaults, asks the user to confirm the correct name, flags any stale caller reference, and does not silently retry with a guess

### Requirement: Vault path resolution
Obsidian SHALL resolve the vault's filesystem root path (via `obsidian vault=<VAULT> vault`) when filesystem operations such as `stat`, `SetFile`, or `mkdir` are needed, and SHALL treat all CLI file paths as relative to that vault root.

#### Scenario: Filesystem operation needed
- **WHEN** a filesystem operation requires the vault's absolute path
- **THEN** Obsidian resolves the vault root path before running the filesystem command

#### Scenario: Interpreting a CLI path
- **WHEN** a path is passed to a CLI command
- **THEN** it is interpreted relative to the vault root

### Requirement: Reading and discovery
Obsidian SHALL read note contents and surface discovery information including file listings, folder listings, recents, per-file info, heading outlines, and word counts.

#### Scenario: Read a note
- **WHEN** the user requests a note's contents by path
- **THEN** Obsidian outputs that note's contents

#### Scenario: Discover vault structure
- **WHEN** the user requests file listings, folder listings, recents, file info, an outline, or a word count
- **THEN** Obsidian returns the corresponding discovery information

### Requirement: Full-text search
Obsidian SHALL search note contents by query text, optionally with surrounding context. Obsidian SHALL NOT use full-text search to resolve tag membership, because broad text matching produces false positives for tag queries.

#### Scenario: Search by text
- **WHEN** the user provides a search query
- **THEN** Obsidian returns matching notes, optionally with surrounding context

#### Scenario: Tag membership requested
- **WHEN** the precise set of files carrying a tag is needed
- **THEN** Obsidian uses the tag command rather than full-text search to avoid false positives

### Requirement: Tag inspection
Obsidian SHALL list all tags with occurrence counts and SHALL list the files containing a specific tag.

#### Scenario: List all tags
- **WHEN** the user requests the vault's tags
- **THEN** Obsidian returns the tags with their occurrence counts

#### Scenario: Files for a specific tag
- **WHEN** the user requests the files carrying a specific tag
- **THEN** Obsidian returns the precise per-tag file list

### Requirement: Property and frontmatter management
Obsidian SHALL read all properties of a file, read a single named property, and set a property value. Property writes SHALL use the CLI's YAML-safe in-place writer so the file's birth time is preserved.

#### Scenario: Read properties
- **WHEN** the user requests a file's properties
- **THEN** Obsidian returns the file's properties

#### Scenario: Set a property
- **WHEN** the user sets a frontmatter property on a file
- **THEN** Obsidian writes the property value in place via the CLI's YAML-safe writer, preserving the file's birth time

### Requirement: Graph and link inspection
Obsidian SHALL report backlinks to a file, outgoing links from a file, orphan files with no incoming links, dead-end files with no outgoing links, and unresolved wikilinks.

#### Scenario: Inspect links for a file
- **WHEN** the user requests backlinks or outgoing links for a file
- **THEN** Obsidian returns the corresponding link set

#### Scenario: Inspect vault-wide link health
- **WHEN** the user requests orphans, dead-ends, or unresolved wikilinks
- **THEN** Obsidian returns the corresponding vault-wide link report

### Requirement: Template access
Obsidian SHALL list all templates and read a template's content.

#### Scenario: List or read templates
- **WHEN** the user requests the available templates or a specific template's content
- **THEN** Obsidian returns the template listing or the requested template's content

### Requirement: Daily notes
Obsidian SHALL read today's daily note, report its path, and append content to it in place.

#### Scenario: Read or locate today's daily note
- **WHEN** the user requests today's daily note or its path
- **THEN** Obsidian returns the daily note's content or path

#### Scenario: Append to today's daily note
- **WHEN** the user appends content to today's daily note
- **THEN** Obsidian appends the content in place, preserving the file's birth time

### Requirement: Note writing operations
Obsidian SHALL append to a file, prepend to a file, create a new file with content, rename a file, move a file, and delete a file (moving it to trash). Append, prepend, rename, and move SHALL write in place and preserve birth time; rename and move SHALL additionally update wikilinks across the vault.

#### Scenario: Append or prepend
- **WHEN** the user appends or prepends content to an existing file
- **THEN** Obsidian writes the content in place, preserving the file's birth time

#### Scenario: Create a file
- **WHEN** the user creates a new file with content
- **THEN** Obsidian creates the file populated with that content

#### Scenario: Rename or move
- **WHEN** the user renames or moves a file
- **THEN** Obsidian relocates the file in place, preserves its birth time, and updates wikilinks across the vault

#### Scenario: Delete a file
- **WHEN** the user deletes a file
- **THEN** Obsidian removes it to trash

### Requirement: Write-approval awareness
Obsidian SHALL treat read-only commands as pre-approved and non-prompting, and SHALL recognize that CLI write operations (`append`, `prepend`, `create`, `delete`, `rename`, `move`, `property:set`) prompt the user for approval unless explicitly pre-approved.

#### Scenario: Read-only command
- **WHEN** a read-only vault command is run
- **THEN** it executes without prompting the user

#### Scenario: Write command
- **WHEN** a CLI write operation is run that is not pre-approved
- **THEN** the user is prompted to approve it

### Requirement: Plugin management
Obsidian SHALL list enabled plugins, list community plugins, report plugin details, and install-and-enable a plugin by id.

#### Scenario: Inspect plugins
- **WHEN** the user requests enabled plugins, community plugins, or details for a plugin id
- **THEN** Obsidian returns the corresponding plugin information

#### Scenario: Install a plugin
- **WHEN** the user installs a plugin by id
- **THEN** Obsidian installs and enables that plugin

### Requirement: Birth-time-preserving write strategy
Obsidian SHALL select a write tool by whether it writes in place. In-place writers (the CLI write commands, `python3` open-for-write, `node fs.writeFileSync`, shell redirect) preserve a vault file's filesystem birth time; tools that atomic-rename (Claude's `Edit`/`Write`) reset birth time on macOS. For in-body content edits, which the CLI cannot perform directly, Obsidian SHALL prefer an in-place writer so birth time is preserved without a follow-up step.

#### Scenario: In-body content edit
- **WHEN** an in-body content edit (find-and-replace, tag rename, structural rewrite) is needed and no CLI command performs it
- **THEN** Obsidian prefers an in-place writer so the file's birth time is preserved without a follow-up step

### Requirement: Birth-time restore after atomic-rename edits
When Claude's `Edit` or `Write` is used on a vault file, Obsidian SHALL pair the operation with a `SetFile` restore. For an existing file, the birth time SHALL be captured before editing and restored afterward; for a newly created file, the birth time SHALL be set to the current time.

#### Scenario: Editing an existing vault file with Edit/Write
- **WHEN** Claude's `Edit` or `Write` modifies an existing vault file
- **THEN** Obsidian captures the file's birth time before the edit and restores it with `SetFile` afterward

#### Scenario: Creating a vault file with Write
- **WHEN** Claude's `Write` creates a new vault file
- **THEN** Obsidian sets the file's birth time to the current time with `SetFile`

### Requirement: Action-tag verb/noun convention
Obsidian SHALL enforce a verb/noun order for action tags (such as `#ask/<person>` and `#todo/<context>`) and SHALL migrate any old noun/verb-format action tags to the verb/noun order when scanning for or creating them.

#### Scenario: Encountering an old-format action tag
- **WHEN** an action tag is found in the old noun/verb order (e.g. `#person/ask`)
- **THEN** Obsidian migrates it to the verb/noun order (e.g. `#ask/person`)

### Requirement: Tag standardization workflow
When asked to standardize tags, Obsidian SHALL obtain the full tag list, identify non-standard patterns, obtain the exact per-tag file list via the tag command (not full-text search), read each file before editing it, and preserve each edited file's birth time.

#### Scenario: Standardizing tags
- **WHEN** the user asks to standardize tags
- **THEN** Obsidian enumerates the tags, resolves the precise per-tag file lists via the tag command, reads each file before editing, and preserves each edited file's birth time

### Requirement: Vault health check workflow
Obsidian SHALL support periodic vault maintenance by reporting orphan notes, dead-end notes, unresolved wikilinks, and a tag-usage audit.

#### Scenario: Running a health check
- **WHEN** the user requests vault maintenance information
- **THEN** Obsidian reports orphans, dead-ends, unresolved wikilinks, and tag usage

### Requirement: Path and value conventions
Obsidian SHALL prefer exact `path=` references when the location is known over name-based resolution, and SHALL quote any value containing spaces.

#### Scenario: Known exact location
- **WHEN** the exact location of a file is known
- **THEN** Obsidian references it via `path=` rather than name-based resolution

#### Scenario: Value contains spaces
- **WHEN** a command value contains spaces
- **THEN** Obsidian quotes the value
