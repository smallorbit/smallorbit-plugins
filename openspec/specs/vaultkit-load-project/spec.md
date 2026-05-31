# Load Project

## Purpose
Load Project brings an Obsidian project's context into the current conversation. When the caller names a project, it loads that project directly; when no name is given, it lists the available projects, recommends the most contextually relevant one, and loads the project the user confirms.

## Requirements

### Requirement: Obsidian connection prerequisite
Load Project SHALL invoke the `vaultkit:obsidian` skill before any other step. It depends on that skill for vault connection details and the command reference, so this invocation MUST happen first regardless of whether a project name was supplied.

#### Scenario: Obsidian invoked first with a project name
- **WHEN** Load Project is invoked with a project name
- **THEN** the `vaultkit:obsidian` skill is invoked before the named project is loaded

#### Scenario: Obsidian invoked first without a project name
- **WHEN** Load Project is invoked without a project name
- **THEN** the `vaultkit:obsidian` skill is invoked before any project listing or recommendation occurs

### Requirement: Named project load
When a project name is provided, Load Project SHALL load that project's context using the `vaultkit:project` skill's load operation, passing through the vault parameter, without listing projects or asking the user to choose.

#### Scenario: Project name supplied
- **WHEN** Load Project is invoked with an explicit project name
- **THEN** it loads the named project via the `vaultkit:project` load-context operation, forwarding the vault parameter, and does not prompt the user to select a project

### Requirement: Context-based recommendation when no name is given
When no project name is provided, Load Project SHALL infer the most likely applicable project from the current conversation context — recent topics, files mentioned, and tasks discussed — and SHALL surface the available projects with that inferred project marked as the recommendation.

#### Scenario: No name supplied
- **WHEN** Load Project is invoked without a project name
- **THEN** it infers a candidate project from conversation context and invokes the `vaultkit:list-projects` skill, passing the vault parameter and the inferred project name as the `recommended` value

### Requirement: Confirmation prompt before loading the recommendation
When no project name is provided, Load Project SHALL ask the user which project to load, stating its recommended guess and the basis for it, rather than loading the inferred project automatically.

#### Scenario: User is prompted to confirm
- **WHEN** Load Project has produced a recommendation for an unnamed request
- **THEN** it asks the user which project to load and names the recommended project as its current-context guess

### Requirement: Load the confirmed selection
After the user confirms the recommendation or chooses a different project, Load Project SHALL load that project's context using the `vaultkit:project` skill's load operation, passing through the vault parameter.

#### Scenario: User confirms the recommendation
- **WHEN** the user confirms the recommended project
- **THEN** Load Project loads that project via the `vaultkit:project` load-context operation, forwarding the vault parameter

#### Scenario: User selects a different project
- **WHEN** the user selects a project other than the recommendation
- **THEN** Load Project loads the user's chosen project via the `vaultkit:project` load-context operation, forwarding the vault parameter

### Requirement: Vault parameter pass-through
Load Project SHALL forward the vault parameter to every downstream skill it invokes so that all operations target the same vault.

#### Scenario: Vault propagated to downstream skills
- **WHEN** Load Project invokes `vaultkit:list-projects` or `vaultkit:project`
- **THEN** it passes the vault parameter through to that skill
