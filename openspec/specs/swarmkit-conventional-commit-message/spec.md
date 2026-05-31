# Conventional Commit Message

## Purpose
Conventional Commit Message defines the canonical commit message format shared across swarmkit — the conventional commits structure, the allowed type enum, the subject-line length limit, and the body guidelines. It is a sub-skill consulted by the commit and swarm flows so every commit they produce follows one consistent, readable standard.

## Requirements

### Requirement: Conventional commits structure
A commit message SHALL follow the conventional commits format, with a subject line of the shape `type(scope): description`.

#### Scenario: Subject line shape
- **WHEN** a commit message is composed
- **THEN** its first line takes the form `type(scope): description`
- **AND** the type is drawn from the allowed type enum

#### Scenario: Single logical change
- **WHEN** a commit is created
- **THEN** the message stays clear and focused on a single logical change

### Requirement: Type enum
The commit type MUST be one of the allowed values, each carrying its defined meaning.

#### Scenario: Allowed type selected
- **WHEN** a commit type is chosen
- **THEN** it is one of: `feat` (new feature), `fix` (bug fix), `chore` (maintenance, dependency updates, no functional change), `refactor` (code reorganization without behavior change), `docs` (documentation changes), `test` (test additions or changes), or `style` (formatting, no functional change)

#### Scenario: Type matches the nature of the change
- **WHEN** the change is, for example, a bug fix
- **THEN** the `fix` type is used rather than an unrelated type

### Requirement: Subject line length
The subject line (first line) MUST stay under 72 characters to preserve readability in `git log --oneline` output.

#### Scenario: Subject within limit
- **WHEN** the subject line is written
- **THEN** it is kept under 72 characters

### Requirement: Body explains the why
When the motivation is not obvious from the diff, the commit SHALL include a body that explains the "why" of the change rather than restating the "what". The body MUST be separated from the subject by a blank line and wrapped at 72 characters for readability.

#### Scenario: Non-obvious motivation
- **WHEN** the reason for a change is not apparent from the diff alone
- **THEN** a body is added that explains the motivation or reason for the change
- **AND** the body describes why the change was made rather than repeating what the code now does

#### Scenario: Body formatting
- **WHEN** a body is present
- **THEN** it is preceded by a blank line after the subject
- **AND** its lines are wrapped at 72 characters

#### Scenario: Self-evident change
- **WHEN** the diff makes the motivation obvious on its own
- **THEN** a body is optional and may be omitted
