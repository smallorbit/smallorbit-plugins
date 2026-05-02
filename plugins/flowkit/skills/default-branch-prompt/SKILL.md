---
name: default-branch-prompt
description: One-time first-run nudge for /open-pr — detects the GitHub default branch and, if it's `main`, prompts the user (via AskUserQuestion) to switch to `develop`. Persists the user's choice via `claude.flowkit.defaultBranchPrompted` so subsequent invocations stay silent. Sub-skill used by open-pr's preflight.
---

# default-branch-prompt

A one-time, opt-in nudge surfaced from `/open-pr`'s preflight. Modern Gitflow-on-GitHub repos increasingly set `develop` as the GitHub default branch — that aligns the auto-close lifecycle (`Closes #N` fires on PRs into the default branch) with where features actually land. Repos that keep `main` as default still work fine; flowkit's `/release` and `/hotfix` skills run an explicit `gh issue close` loop after the merge, so the lifecycle completes either way.

This skill exists as its own file (rather than inline in `open-pr/SKILL.md`) because the prompt logic is several distinct steps — detect, gate on a marker, ask, confirm, mutate, persist — and inlining it would crowd open-pr's already long preflight section. Open-pr calls it as the first preflight step; everything else can assume the prompt has either fired (and been answered) or been skipped silently.

## When to invoke

Open-pr's preflight calls this skill before checking the current branch. The skill is a no-op in every case except the narrow first-run-on-`main`-default scenario described below.

## Process

### 1. Skip if the marker is set

```bash
if [ "$(git config --get claude.flowkit.defaultBranchPrompted 2>/dev/null)" = "true" ]; then
  exit 0
fi
```

The marker is repo-local and persists across sessions. Once set (by any of the three answer paths below), this skill never prompts again in this repo.

### 2. Detect the GitHub default branch

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
```

Treat any non-zero exit, missing `gh` binary, missing auth, or empty result as **skip silently** — do not pester the user when detection fails for environmental reasons. Open-pr's later steps already handle the "no `gh`" case loudly; that's where the user should learn about it, not here.

```bash
if [ -z "$DEFAULT_BRANCH" ]; then
  exit 0
fi
```

### 3. Only prompt when the default is exactly `main`

```bash
if [ "$DEFAULT_BRANCH" != "main" ]; then
  exit 0
fi
```

Any other default branch (including `develop`, `master`, or a custom name) means the user has already made a deliberate choice — leave them alone.

### 4. Ask the user

Invoke `AskUserQuestion` with the following shape:

- **Question**: "Your repo's GitHub default branch is `main`. Flowkit recommends `develop` as the default for new flowkit users — modern Gitflow-on-GitHub convention, and it makes `Closes #N` auto-close fire on the PRs that actually carry the work. The switch is `gh repo edit --default-branch develop`. Existing `main`-as-default setups continue to work; this is a recommendation, not a requirement."
- **Options** (exactly three):
  1. `Switch to develop` — run `gh repo edit --default-branch develop` after a confirmation step
  2. `Keep main as default` — semantically: "I considered the recommendation and chose `main`." Sets the marker. The repo is unchanged.
  3. `Don't ask again` — semantically: "Stop bothering me — I haven't decided yet." Sets the marker. The repo is unchanged.

Both `Keep main as default` and `Don't ask again` set the same marker and produce the same observable outcome (no repo change, no future prompts). They are presented as separate options because the distinction matters socially: a user who consciously chose `main` should not have to pretend they're dismissing the prompt out of annoyance, and a user who's not ready to decide should not have to commit to a position they haven't formed yet. Future readers of this skill should preserve both options for that reason.

### 5. Handle the answer

#### `Switch to develop`

Surface a **second** `AskUserQuestion` confirming the destructive-ish change before running it. The confirmation question wording:

> About to run `gh repo edit --default-branch develop`. This changes the GitHub repository's default branch — visible to all collaborators and tooling that reads the default. Confirm?

Options:

- `Yes, change the default branch to develop`
- `Cancel`

On `Yes`:

```bash
gh repo edit --default-branch develop
```

If the command succeeds, set the marker:

```bash
git config claude.flowkit.defaultBranchPrompted true
```

If the command fails (non-zero exit), report the error to the user and **do not** set the marker — that way the next `/open-pr` invocation will give them another chance to retry once they've fixed permissions or auth.

On `Cancel`: do nothing. The marker stays unset, so the next `/open-pr` invocation will surface the original three-option prompt again. (Cancelling the confirmation is not the same as choosing `Don't ask again`.)

#### `Keep main as default`

```bash
git config claude.flowkit.defaultBranchPrompted true
```

No repo mutation. Report a single line: "Keeping `main` as the default branch. Flowkit's release flow handles `Closes #N` issue-close at release time."

#### `Don't ask again`

```bash
git config claude.flowkit.defaultBranchPrompted true
```

No repo mutation. Report a single line: "OK, won't ask again. Re-run by clearing the marker: `git config --unset claude.flowkit.defaultBranchPrompted`."

## Constraints

- **Never automatic.** Every action that mutates the repo or the marker requires an explicit user answer. This skill does not run `gh repo edit` without the second confirmation, and it does not set the marker without a user choice.
- **Detection failure is silent.** Missing `gh`, no auth, network errors, or any non-zero exit from `gh repo view` skip the prompt without warning. Open-pr's main flow surfaces gh-related errors on its own.
- **Marker is repo-local.** `git config` (without `--global`) writes to the repo's `.git/config`, which is the right scope: a user's preference for one repo should not leak to another.
- **Only `main` triggers the prompt.** Any other default branch is treated as a deliberate choice and left alone.
- **Never use the legacy `claude.prBase` key.** The marker key is `claude.flowkit.defaultBranchPrompted` and lives under the `claude.flowkit.*` namespace.

## Resetting

To re-surface the prompt (e.g., after migrating between repos or for testing):

```bash
git config --unset claude.flowkit.defaultBranchPrompted
```

The next `/open-pr` invocation will run through the detect-and-prompt flow from scratch.
