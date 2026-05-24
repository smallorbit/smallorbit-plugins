---
name: default-branch-prompt
description: One-time first-run nudge for /open-pr — detects the GitHub default branch and, if it's `main`, prompts the user (via AskUserQuestion) to switch to `develop`. Persists the user's choice via `claude.flowkit.defaultBranchPrompted` so subsequent invocations stay silent. Sub-skill used by open-pr's preflight.
---

# default-branch-prompt

One-time nudge fired by `/open-pr` before checking the current branch. No-op in every case except first-run-on-`main`-default. After returning, `open-pr` continues regardless of outcome.

## Process

### 1. Skip if the marker is set

```bash
if [ "$(git config --get claude.flowkit.defaultBranchPrompted 2>/dev/null)" = "true" ]; then
  exit 0
fi
```

Once set, never prompts again in this repo.

### 2. Detect the GitHub default branch

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
```

On any non-zero exit, missing `gh`, no auth, or empty result: skip silently. `open-pr` already surfaces `gh` errors in its main flow.

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

Any other value means the user has already made a deliberate choice — leave them alone.

### 4. Ask the user

Invoke `AskUserQuestion` with the following shape:

- **Question**: "Your repo's GitHub default branch is `main`. Flowkit recommends `develop` as the default for new flowkit users — modern Gitflow-on-GitHub convention, and it makes `Closes #N` auto-close fire on the PRs that actually carry the work. The switch is `gh repo edit --default-branch develop`. Existing `main`-as-default setups continue to work; this is a recommendation, not a requirement."
- **Options** (exactly three):
  1. `Switch to develop` — run `gh repo edit --default-branch develop` after a confirmation step
  2. `Keep main as default` — "I chose `main` deliberately." Sets the marker. No repo mutation.
  3. `Don't ask again` — "Not deciding yet." Sets the marker. No repo mutation.

Both options 2 and 3 produce the same outcome (marker set, no change, no future prompts) but are presented as distinct choices so a deliberate `main` user and an undecided user each have an honest answer. Preserve both options.

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

On success, set the marker. On failure, report the error and **do not** set the marker — the next `/open-pr` gives them another chance.

On `Cancel`: marker stays unset; the three-option prompt resurfaces next time.

#### `Keep main as default`

```bash
git config claude.flowkit.defaultBranchPrompted true
```

Report: "Keeping `main` as the default branch. Flowkit's release flow handles `Closes #N` issue-close at release time."

#### `Don't ask again`

```bash
git config claude.flowkit.defaultBranchPrompted true
```

Report: "OK, won't ask again. Re-run by clearing the marker: `git config --unset claude.flowkit.defaultBranchPrompted`."

## Reset

To re-surface the prompt: `git config --unset claude.flowkit.defaultBranchPrompted`.
