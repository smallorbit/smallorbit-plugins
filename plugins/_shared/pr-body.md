# Canonical PR Body Specification

Every PR opened by plugins in this repo uses the shape defined here. This is the single source of truth — skills that emit PR bodies reference this document rather than carrying their own copy.

## Body shape

A PR body has three sections in this order, followed by a footer of issue-reference tokens.

### `## Summary`

1–3 sentences derived from the diff and the commit messages on the branch. State what the change does and why. No bullets. No file paths. No restating the title.

### `## Changes`

Bulleted list of concrete changes, each with a file reference where applicable. One bullet per logical change, not per file. Group related edits. Keep bullets tight — a reviewer should be able to scan the list and predict the diff.

### `## Test plan`

Bulleted checklist (`- [ ]`) of verification steps. Each item is something a reviewer or CI can actually check. Prefer behavioral checks ("PR body renders with all three sections") over implementation checks ("function returns correct value"). If the change is pure docs or config, the checklist may be short — but it must exist.

## Issue-reference footer

After the three sections, emit a blank line, then one token per line using GitHub's closing-keyword grammar.

| Token | When to use |
|-------|-------------|
| `Closes #N` | The child issue `#N` is fully resolved by this PR. GitHub will auto-close it on merge to the default branch. |
| `Refs #N` | The parent epic `#N`, or any issue this PR only partially advances. Does not auto-close. |

> **Important:** GitHub only parses one closing keyword per line. `Closes #A #B #C` on a single line silently leaves `#B` and `#C` open — only `#A` is treated as a closing reference. Always emit one token per line (`Closes #A` / `Closes #B` / `Closes #C`).

Rules:

- Emit one `Closes #N` line per fully-resolved child issue.
- Emit one `Refs #N` line for the parent epic, if any.
- Emit additional `Refs #N` lines for partial-progress references (PR advances the issue but does not close it).
- Do not use `Fixes` or `Resolves` in newly authored bodies — they are accepted by downstream aggregators for back-compat but `Closes` is canonical here.

## Worked example

```markdown
## Summary

Standardize the PR body shape across flowkit and swarmkit so reviewers see the same three sections on every PR and release-time ref aggregation picks up every `Closes` token. The convention now lives in one file instead of being duplicated across skills.

## Changes

- Author `plugins/_shared/pr-body.md` as the canonical spec (this file).
- Update `plugins/flowkit/skills/open-pr/SKILL.md` to reference the canonical shape and forward commit-message tokens to the footer.
- Update `plugins/swarmkit/skills/swarm/SKILL.md` agent template to reference the canonical Summary rules.

## Test plan

- [ ] Open a PR via `flowkit:open-pr` and confirm the body has `## Summary`, `## Changes`, and `## Test plan`.
- [ ] Include `Closes #123` in a commit message; confirm it appears in the PR footer.
- [ ] Run `flowkit:release` and confirm ref aggregation still collects `Closes` tokens from merged PRs.
- [ ] Spawn a `swarmkit:swarm` agent and confirm its PR emits `## Summary` + `## Test plan` + `Closes #<issue>`.

Closes #521
Closes #522
Refs #526
Refs #530
```

In this example: `#521` and `#522` are fully-resolved child issues that auto-close on merge; `#526` is the parent epic (kept open); `#530` is a related issue this PR advances but does not finish.
