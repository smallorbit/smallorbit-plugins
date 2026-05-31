# List Projects

## Purpose
List Projects enumerates every project in an Obsidian vault's `Projects/` folder and presents them as a status-sorted table followed by a count summary. It is a read-only sub-skill used by `vaultkit:load-project` to surface the projects a user can load, optionally highlighting one recommended project.

## Requirements

### Requirement: Obsidian dependency
List Projects SHALL invoke the `vaultkit:obsidian` skill before performing any operation, because it depends on that skill's vault connection details and command reference.

#### Scenario: Skill is invoked
- **WHEN** List Projects begins
- **THEN** it invokes the `vaultkit:obsidian` skill first, before listing any projects

### Requirement: Vault parameter required
List Projects SHALL require a vault name for all operations and SHALL expect the caller to supply it explicitly. When no vault name is given, List Projects SHALL list the available vaults, present them to the user, and ask which vault to use before continuing.

#### Scenario: Vault name supplied
- **WHEN** the caller supplies a vault name
- **THEN** List Projects proceeds against that vault

#### Scenario: Vault name omitted
- **WHEN** no vault name is supplied
- **THEN** List Projects lists the available vaults, presents them to the user, and asks which vault to use before continuing

### Requirement: Enumerate vault projects
List Projects SHALL enumerate every project folder under the selected vault's `Projects/` folder.

#### Scenario: Projects folder contains projects
- **WHEN** the vault's `Projects/` folder contains one or more project folders
- **THEN** List Projects produces an entry for each project found

### Requirement: Resolve per-project status
List Projects SHALL determine each project's status from the `status` field of that project's `Overview.md`. It SHALL read the status for every enumerated project.

#### Scenario: Status read for each project
- **WHEN** the project folders have been enumerated
- **THEN** List Projects reads the `status` field from each project's `Overview.md`

### Requirement: Status-sorted table output
List Projects SHALL display the projects as a formatted table with a Project column and a Status column, sorted by status in the order active first, then on-hold, then done.

#### Scenario: Table rendered in status order
- **WHEN** the projects and their statuses are known
- **THEN** List Projects renders a Project/Status table ordered active, then on-hold, then done

### Requirement: Recommended-project highlighting
When the caller passes a `recommended` project name, List Projects SHALL bold that project's row and append a `← recommended` marker to it. When no recommended name is passed, no row is highlighted.

#### Scenario: Recommended name passed
- **WHEN** the caller passes a `recommended` project name
- **THEN** the matching row is bolded and marked with `← recommended`

#### Scenario: No recommended name passed
- **WHEN** the caller passes no recommended project name
- **THEN** no row is bolded or marked as recommended

### Requirement: Count summary
List Projects SHALL display a count summary after the table, breaking down how many projects fall into each status (for example `5 active · 2 on-hold · 1 done`).

#### Scenario: Summary follows the table
- **WHEN** the table has been rendered
- **THEN** List Projects shows a count summary of projects per status beneath it

### Requirement: Read-only sub-skill role
List Projects SHALL operate as a read-only sub-skill consumable by `vaultkit:load-project`, producing only the listing as output and leaving the vault unchanged.

#### Scenario: Invoked as a sub-skill
- **WHEN** `vaultkit:load-project` invokes List Projects to discover available projects
- **THEN** List Projects returns the listing without creating, modifying, or deleting any vault files
