# Issue Rank

## Purpose
Issue Rank is the canonical ranking reference that consuming skills (next-issue and swarm) apply when prioritizing open GitHub issues. It defines a weighted signal table, deeper assessment criteria for top candidates, and tie-breaking guidance so issue selection is consistent across the suite.

## Requirements

### Requirement: Weighted ranking table
Issue Rank SHALL define a canonical table that assigns a relative weight to each prioritization signal. The signals and their weights MUST be: a `priority:high` label (Highest), a `priority:medium` label (High), subtasks already defined in the issue body (High, on the basis of lower friction), architectural impact that unblocks other work (High), a `priority:low` or `cleanup` label (Low), and no label at all (Medium, requiring the body to be read to judge).

#### Scenario: Priority-labeled issue weighted
- **WHEN** an issue carries a `priority:high` label
- **THEN** it receives the Highest weight in the ranking
- **AND** a `priority:medium` label receives High weight while a `priority:low` or `cleanup` label receives Low weight

#### Scenario: Lower-friction issue weighted up
- **WHEN** an issue body already defines subtasks, or the issue has architectural impact that unblocks other work
- **THEN** it receives High weight

#### Scenario: Unlabeled issue weighted
- **WHEN** an issue carries no priority label
- **THEN** it receives Medium weight and its body MUST be read to judge its true priority

### Requirement: Deeper assessment criteria
For deeper evaluation of the top candidates surfaced by the ranking table, Issue Rank SHALL apply four assessment criteria: specificity (whether exact files, line numbers, or interfaces are called out, where more specific means lower risk), scope (whether the change is focused and atomic or a sprawling refactor), dependencies (whether the issue blocks or unblocks other open issues), and testability (whether the outcome can be verified mechanically, such as via type-checking, tests, or text search).

#### Scenario: Top candidate evaluated in depth
- **WHEN** a candidate issue rises to the top of the ranking and warrants deeper evaluation
- **THEN** it is assessed against specificity, scope, dependencies, and testability
- **AND** higher specificity, narrower scope, unblocking dependencies, and mechanical testability all favor selecting the issue

### Requirement: Priority surfacing guarantee
Issue Rank SHALL guarantee that whenever `priority:high` issues exist they are always surfaced and never buried behind architectural preferences. It SHALL also recognize that a well-specced `priority:medium` issue can be preferred over a vague `priority:high` issue when the work is intended for autonomous agents.

#### Scenario: High-priority issues present
- **WHEN** one or more `priority:high` issues exist in the candidate set
- **THEN** they are always surfaced and SHALL NOT be hidden behind architectural-impact preferences

#### Scenario: Well-specced medium beats vague high
- **WHEN** a well-specified `priority:medium` issue is compared against a vague `priority:high` issue for autonomous agent work
- **THEN** the well-specified `priority:medium` issue may be ranked ahead of the vague `priority:high` issue
