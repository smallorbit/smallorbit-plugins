# Open PR

## Purpose

Push the current branch to origin and open a GitHub pull request against the base branch (`main` by default, or a pinned/overridden base). It assembles a canonical three-section PR body, forwards issue-reference tokens discovered in the branch's commits, and guards against protected-branch and malformed-footer mistakes.

## Requirements

### Requirement: Protected Branch Guard
The skill SHALL refuse to open a PR when the current branch is a protected branch (`main` or `master`) and SHALL stop immediately, directing the operator to check out a feature branch first.

#### Scenario: Protected branch blocked
- **WHEN** the current branch is `main` or `master`
- **THEN** the skill stops immediately without pushing or opening a PR
- **AND** reports that a PR cannot be opened from a protected branch and that a feature branch must be checked out first

#### Scenario: Feature branch proceeds
- **WHEN** the current branch is any branch other than `main` or `master`
- **THEN** the skill proceeds to resolve the base branch and continue the flow

### Requirement: Base Branch Resolution
The skill SHALL resolve the base branch via a deterministic chain: an explicit `--base` token in the arguments, then the `claude.flowkit.prBase` config key, then a default of `main`. The resolved base SHALL be non-empty and SHALL NOT equal the current HEAD branch.

#### Scenario: Explicit --base flag wins
- **WHEN** the arguments contain a `--base <branch>` (or `--base=<branch>`) token
- **THEN** that branch is used as the base and later resolution steps are skipped

#### Scenario: Config key consulted after explicit arg
- **WHEN** no `--base` token is supplied and `claude.flowkit.prBase` is set
- **THEN** the config value is used as the base

#### Scenario: Default to main
- **WHEN** no `--base` token is supplied and `claude.flowkit.prBase` is unset
- **THEN** the base defaults to `main`

#### Scenario: Self-targeting guard rejects base equal to HEAD
- **WHEN** the resolved base equals the current HEAD branch
- **THEN** the skill exits non-zero with guidance to either rerun with an explicit `--base` override or unset the `claude.flowkit.prBase` pin

### Requirement: Branch Push
The skill SHALL push the current branch to origin with upstream tracking using `git push -u origin HEAD`. It SHALL NOT force-push.

#### Scenario: Branch pushed with upstream tracking
- **WHEN** the base branch has been resolved
- **THEN** the current branch is pushed via `git push -u origin HEAD`

#### Scenario: Force-push never used
- **WHEN** the current branch is pushed
- **THEN** no `--force` or `--force-with-lease` flag is used

### Requirement: PR Title Derivation
The skill SHALL determine the PR title from the first applicable source: the arguments when they read like a short title, then the most recent commit message subject line, then the branch name converted to title case with its type prefix stripped and hyphens replaced by spaces.

#### Scenario: Arguments used as title
- **WHEN** the arguments are provided and read like a short title phrase
- **THEN** that phrase is used as the PR title

#### Scenario: Commit subject used when no title argument
- **WHEN** no title-like argument is provided
- **THEN** the most recent commit's subject line is used as the PR title

#### Scenario: Branch name fallback
- **WHEN** no title-like argument and no usable commit subject are available
- **THEN** the branch name is converted to a title (prefix stripped, hyphens replaced by spaces) and used as the PR title

### Requirement: Issue-Reference Token Discovery
The skill SHALL scan every commit on the branch since divergence from the resolved base for issue-reference tokens matching `closes|fixes|refs|resolves #<number>` case-insensitively, emit each match verbatim preserving the author's original casing and keyword, and deduplicate while keeping first-seen order.

#### Scenario: Tokens collected from branch commits
- **WHEN** commits since divergence from the base contain closing-keyword references such as `Fixes #12`
- **THEN** those tokens are collected for the PR body footer

#### Scenario: Verbatim forwarding of author casing and keyword
- **WHEN** an issue-ref token is discovered in a commit message
- **THEN** it is emitted verbatim, preserving the original casing and keyword choice (`Fixes`/`Resolves`/`Closes`/`Refs`) rather than being rewritten

#### Scenario: Duplicate tokens deduplicated in first-seen order
- **WHEN** the same issue reference appears in multiple commits
- **THEN** it appears only once in the footer, in first-seen order, with case-insensitive deduplication

#### Scenario: No references present
- **WHEN** no commit on the branch contains an issue-reference token
- **THEN** the footer is empty and the PR body carries no issue references

### Requirement: PR Body Assembly
The skill SHALL assemble a canonical PR body with three sections in order — `## Summary` (a 1–3 sentence narrative), `## Changes` (bulleted concrete changes, one per logical change), and `## Test plan` (a `- [ ]` checklist of verifiable steps) — followed by a blank line and the discovered issue-reference tokens, one per line.

#### Scenario: Three sections in order
- **WHEN** the PR body is assembled
- **THEN** it contains `## Summary`, `## Changes`, and `## Test plan` headings in that order

#### Scenario: Summary derived from diff and commits
- **WHEN** the Summary section is built
- **THEN** it is a 1–3 sentence narrative synthesized from the branch's commit messages and diff, informed by the arguments when they contain a longer description

#### Scenario: Footer appended after a blank line
- **WHEN** issue-reference tokens were discovered
- **THEN** they are appended after the body sections, separated by a blank line, with one token per line

### Requirement: Footer Lint For Packed Closing Keywords
The skill SHALL reject the assembled body before opening the PR if any line packs multiple issue references onto a single closing keyword (e.g. `Closes #1 #2 #3`). It SHALL fail loudly with guidance to rewrite one token per line, and SHALL NOT auto-rewrite the footer.

#### Scenario: Space-separated multi-ref footer rejected
- **WHEN** the assembled body contains a line such as `Closes #1 #2 #3`
- **THEN** the skill exits non-zero before calling the PR-create command
- **AND** reports that GitHub parses only one closing keyword per line and shows the one-token-per-line rewrite

#### Scenario: Well-formed footer accepted
- **WHEN** every closing-keyword line references exactly one issue
- **THEN** the lint passes and the skill proceeds to open the PR

### Requirement: Open The Pull Request
The skill SHALL open the pull request by passing the resolved base explicitly, the current branch as head, the derived title, and the assembled body. The resolved base is guaranteed non-empty by the base-resolution step.

#### Scenario: PR created with explicit base and head
- **WHEN** the body has passed the footer lint
- **THEN** the PR is created with `--base` set to the resolved base, `--head` set to the current branch, the derived title, and the assembled body

#### Scenario: PR URL reported
- **WHEN** the PR is created
- **THEN** the returned PR URL is output to the operator

### Requirement: Tooling Preconditions
The skill SHALL stop and report the error when the GitHub CLI is not installed or not authenticated, and SHALL NOT attempt workarounds.

#### Scenario: GitHub CLI unavailable
- **WHEN** the GitHub CLI is not installed or not authenticated
- **THEN** the skill reports the error and stops without attempting any workaround
