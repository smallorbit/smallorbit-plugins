# Next Issue

## Purpose

Next Issue fetches the open GitHub issues for a repository, ranks them by priority, implementation specificity, and architectural impact, and recommends the single best issue to work on next plus a runner-up. It is a read-only advisory skill: it surfaces a recommendation and waits for the operator to choose, never starting implementation itself.

## Requirements

### Requirement: Issue fetching and filtering

Next Issue SHALL fetch the open GitHub issues for the repository and SHALL exclude issues that are not actionable before ranking — specifically issues labeled to indicate they are on hold and issues labeled to indicate they are already in progress with an active agent.

#### Scenario: Open issues fetched and filtered

- **WHEN** Next Issue gathers candidates
- **THEN** it retrieves the open issues
- **AND** it removes issues marked as on hold because they are not ready to work
- **AND** it removes issues marked as in progress because they are already in flight

#### Scenario: No issues available

- **WHEN** the filtered issue list is empty
- **THEN** Next Issue reports that there are no issues to recommend
- **AND** it suggests generating new issues from codebase findings as a next step

### Requirement: Candidate ranking and detail gathering

Next Issue SHALL rank the remaining issues by priority, implementation specificity, and architectural impact, and SHALL read the full body of the top candidates before forming a recommendation.

#### Scenario: Ranking and inspecting top candidates

- **WHEN** actionable issues remain after filtering
- **THEN** Next Issue ranks them by priority, specificity, and impact
- **AND** it reads the full body of the top handful of candidates to inform the recommendation

### Requirement: Ranked summary output

Next Issue SHALL present a ranked summary of the top candidates that, for each candidate, includes its issue number, title, priority, and a concise reason to consider it.

#### Scenario: Presenting the ranked summary

- **WHEN** Next Issue has ranked the candidates
- **THEN** it outputs a summary listing each top candidate with its number, title, priority, and a short rationale for consideration

### Requirement: Recommendation with runner-up

Next Issue SHALL state a single primary recommendation with a brief rationale and SHALL state a runner-up alternative with the tradeoff that would make it preferable.

#### Scenario: Stating the recommendation

- **WHEN** Next Issue delivers its advice
- **THEN** it names one primary issue to start now with a short rationale
- **AND** it names a runner-up to choose instead if the primary seems too large or risky, explaining the tradeoff

### Requirement: File-conflict flagging

Next Issue SHALL flag when two recommended issues touch the same files so the operator can sequence them rather than running them in parallel.

#### Scenario: Overlapping issues detected

- **WHEN** two candidate issues would modify the same files
- **THEN** Next Issue flags the overlap so the operator can sequence the work

### Requirement: Read-only advisory operation

Next Issue SHALL NOT start implementation, modify issues, create branches, or change code. It SHALL stop after presenting the recommendation and wait for the operator to choose how to proceed.

#### Scenario: Recommendation delivered

- **WHEN** Next Issue finishes presenting its recommendation
- **THEN** it does not begin implementing any issue
- **AND** it waits for the operator to confirm which issue to work on and how to proceed
