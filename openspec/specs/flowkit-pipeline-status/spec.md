# Pipeline Status

## Purpose
Pipeline Status reports the state of the release pipeline at a glance so the operator knows what to do next. Under the single-trunk GitHub Flow surface there are two stages — open PRs in flight targeting `main`, and the most recent release tag — and the skill is read-only, refreshing remote state before printing both stages and an actionable next-step suggestion.

## Requirements

### Requirement: Read-only operation
Pipeline Status SHALL be read-only. It SHALL NOT mutate any branch, tag, pull request, label, or other repository state; its only output is the rendered pipeline report.

#### Scenario: No mutation during a run
- **WHEN** the skill runs
- **THEN** no branch, tag, PR, or label is created, modified, or deleted

### Requirement: Fetch latest remote state first
Pipeline Status SHALL refresh remote state before reading any pipeline data, so the report reflects the current state of origin rather than a stale local snapshot.

#### Scenario: Fetch precedes any read
- **WHEN** the skill starts
- **THEN** the latest remote state is fetched from origin before any open-PR or tag data is read

### Requirement: Two-stage pipeline collection
Pipeline Status SHALL collect two stages of pipeline data: in-flight open pull requests that target `main`, and the most recent release tag. The release tag SHALL be the globally highest `v*` tag, excluding per-plugin tags (those whose name contains `--v`), and the skill SHALL compute the number of commits on `main` since that tag. When no release tag exists, the count SHALL be the total number of commits on `main`.

#### Scenario: In-flight PRs gathered
- **WHEN** the skill collects pipeline data
- **THEN** the set of open pull requests whose base is `main` is gathered, including each PR's number, title, author, draft state, review decision, merge state, and age

#### Scenario: Latest release tag selected excluding per-plugin tags
- **WHEN** the most recent release tag is resolved
- **THEN** per-plugin tags (names containing `--v`) are excluded and the globally highest `v*` tag is chosen

#### Scenario: Unreleased commit count computed
- **WHEN** a release tag exists
- **THEN** the number of commits on `main` since that tag is computed as the unreleased count

#### Scenario: No release tag yet
- **WHEN** no `v*` release tag exists
- **THEN** the unreleased count is the total number of commits on `main`

### Requirement: Always print every stage
Pipeline Status SHALL print both stages in pipeline order (in flight → released), and SHALL print every stage even when it is empty, using a "none" indicator for empty sections so the empty state is itself reported as information.

#### Scenario: Stages printed in pipeline order
- **WHEN** the report is rendered
- **THEN** the in-flight stage is shown before the released stage

#### Scenario: Empty stage still shown
- **WHEN** a stage has no entries
- **THEN** the stage is still printed with "none" rather than omitted

### Requirement: Per-PR row formatting
For each open PR, Pipeline Status SHALL render a row containing the PR number, a review-status label, a merge-state label, the title, the author, and the age. The review-status label SHALL be derived from the review decision — approved maps to APPROVED, changes-requested maps to CHANGES_REQUESTED, and review-required or unknown maps to NEEDS_REVIEW — and a draft PR SHALL be labeled DRAFT, which takes precedence over any review decision. The merge-state label SHALL be derived from the merge state — clean maps to `clean`, blocked or behind maps to `blocked`, dirty or unstable maps to a conflicts/ci-failing indicator, and any other value is shown lowercased verbatim.

#### Scenario: Approved clean PR row
- **WHEN** a non-draft PR is approved with a clean merge state
- **THEN** its row shows the APPROVED review status and the `clean` merge state

#### Scenario: Draft precedence over review status
- **WHEN** a PR is a draft
- **THEN** its review-status label is DRAFT regardless of its underlying review decision

#### Scenario: Unknown merge state shown verbatim
- **WHEN** a PR's merge state is not one of the recognized values
- **THEN** the raw merge-state value is shown lowercased

### Requirement: Next-step suggestion priority
Pipeline Status SHALL emit a single actionable next-step suggestion chosen by first-matching-rule priority: a PR with failing CI or merge conflicts yields "resolve blockers"; otherwise an approved PR with a clean merge state yields "merge it"; otherwise a non-draft unreviewed PR yields "review open PRs"; otherwise commits on `main` since the last release tag yield "run the ship release"; otherwise "nothing to ship". Draft PRs SHALL NOT trigger the review suggestion.

#### Scenario: Blockers take top priority
- **WHEN** at least one open PR has failing CI or merge conflicts
- **THEN** the suggestion directs the operator to resolve blockers on that PR, regardless of other states

#### Scenario: Approved clean PR suggested for merge
- **WHEN** no PR is blocked and at least one open PR is approved with a clean merge state
- **THEN** the suggestion directs the operator to merge that PR

#### Scenario: Unreviewed non-draft PRs suggested for review
- **WHEN** no PR is blocked or approved-and-clean, and at least one non-draft PR is unreviewed
- **THEN** the suggestion directs the operator to review the open PRs

#### Scenario: Unreleased commits suggest shipping
- **WHEN** no open PR triggers a suggestion and there are commits on `main` since the last release tag
- **THEN** the suggestion directs the operator to run the ship release

#### Scenario: Nothing pending
- **WHEN** there are no open PRs and no commits on `main` since the last release tag
- **THEN** the suggestion is "nothing to ship"

#### Scenario: Drafts never trigger review suggestion
- **WHEN** the only unreviewed PRs are drafts
- **THEN** the "review open PRs" suggestion does not fire
