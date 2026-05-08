---
name: cut-epic
description: Cut a long-lived `feature/<slug>-<issue>` branch from origin/develop, push it to origin, and pin `claude.flowkit.prBase` so subsequent PRs target it. Use when starting a multi-PR epic that should stay isolated from develop until ready to ship.
triggers:
  - "/cut-epic"
  - "start an epic"
  - "cut an epic branch"
  - "create epic branch"
  - "feature branch for epic"
allowed-tools: Bash
---

# Cut Epic

Create a long-lived feature branch for a multi-PR epic, push it to origin, and scope `claude.flowkit.prBase` to it so every subsequent `/open-pr` and `/pr` (and every `swarmkit:swarm` agent in the session) targets the epic branch instead of `develop`.

The epic branch lives until the epic ships. When it's ready, open a single PR from the epic branch to `develop`, then run the teardown (see below) to clear the scope.

## Input

`$ARGUMENTS` — required. Either:

1. An issue number (e.g. `1264`) — slug is inferred from the issue title via `gh issue view`.
2. An issue number plus a slug (e.g. `1264 onboarding-v2` or `onboarding-v2 1264`) — slug is used verbatim.
3. A full branch name already prefixed with `feature/` — used as-is after validation.

If no arguments are provided, stop and ask for an issue number.

## Process

### 1. Resolve the epic branch name

Determine `<issue>` and `<slug>`:

- If `$ARGUMENTS` is a single number, treat it as the issue number and infer the slug:
  ```bash
  TITLE=$(gh issue view "$ISSUE" --json title --jq .title)
  SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | cut -c1-40 | sed -E 's/-+$//')
  ```
- If `$ARGUMENTS` contains both a number and a kebab-case word, use them as `<issue>` and `<slug>` regardless of order.
- If `$ARGUMENTS` is already a `feature/...` branch name, skip slug inference and use it directly.

Assemble the branch name:

```
feature/<slug>-<issue>
```

Examples:
- Issue 1264 titled "Onboarding v2" → `feature/onboarding-v2-1264`
- `$ARGUMENTS = "1264 onboarding-v2"` → `feature/onboarding-v2-1264`
- `$ARGUMENTS = "feature/onboarding-v2-1264"` → used as-is

### 2. Validate

Reject the following outright — do not create them:
- `main`, `master`, `develop`
- Any name without the `feature/` prefix (after auto-prefixing in step 1)

The full branch name must be 60 characters or fewer. If the slug pushes it over, truncate the slug, not the issue number.

### 3. Fetch latest remote state

```bash
git fetch origin
```

### 4. Create the epic branch from origin/develop

If the branch already exists locally or on origin, do not recreate it — check it out and reuse it. This keeps the skill idempotent for resumed sessions.

```bash
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git checkout -b "$BRANCH" "origin/$BRANCH"
else
  git checkout -b "$BRANCH" origin/develop
fi
```

### 5. Push to origin

```bash
git push -u origin "$BRANCH"
```

If the branch already tracks origin, this is a no-op.

### 6. Scope `claude.flowkit.prBase` to the epic branch

Delegate to the `pr-base-scope` sub-skill — do not duplicate its config-write logic:

```bash
git config claude.flowkit.prBase "$BRANCH"
```

This is the same operation `pr-base-scope` performs in its **Set** mode. From now on, every `flowkit:open-pr` and `flowkit:pr` invocation in this repo (and every `swarmkit:swarm` agent that inherits the repo config) will target `$BRANCH` as the PR base.

### 7. Report

Print a confirmation including the branch name, the upstream, and the scoped config. Suggest the next step:

> Epic branch `feature/onboarding-v2-1264` created from `origin/develop` and pushed.
> `claude.flowkit.prBase` is now scoped to this branch.
> Sub-PRs opened in this repo will target `feature/onboarding-v2-1264` until you tear down the scope.

## Composition

| Caller | Behavior |
|--------|----------|
| `flowkit:open-pr` | Reads `claude.flowkit.prBase` and targets the epic branch automatically. |
| `flowkit:pr` | Same — branches off `origin/develop` for sub-work, but PRs target the epic branch. |
| `swarmkit:swarm` | Loop-mode agents inherit the scoped base; each spawned PR targets the epic branch. Combine with `swarmkit:merge-stack` to fan child PRs into the epic branch. |
| `flowkit:ship` | Will override `claude.flowkit.prBase` to `develop` for its own flow, then unset. **Do not run `/ship` while an epic is in flight** unless you intend to ship the epic itself. |

## Teardown

When the epic is ready to ship, run `flowkit:ship-epic`. It opens the epic-to-`develop` PR, rebase-merges (so children's squashes replay onto develop linearly), unsets `claude.flowkit.prBase`, deletes the epic branch, and fast-forwards local develop. See [`ship-epic/SKILL.md`](../ship-epic/SKILL.md) for full details.

To close out by hand (manual fallback):

1. Open a final PR from the epic branch into `develop`:
   ```bash
   gh pr create --base develop --head feature/<slug>-<issue>
   ```
2. Rebase-merge via the GitHub UI or CLI (`gh pr merge --rebase --delete-branch`).
3. Clear the scope so future PRs default back to `develop`:
   ```bash
   git config --unset claude.flowkit.prBase
   ```
4. (Optional) Delete the local epic branch:
   ```bash
   git branch -D feature/<slug>-<issue>
   ```

## Constraints

- Always branch from `origin/develop`, never from a local `develop` (which may be behind).
- Never write a non-`feature/` prefix — this skill is purposely narrow.
- Never modify `claude.prBase` (the legacy key) — only `claude.flowkit.prBase`. See `pr-base-scope` for the rationale.
- Idempotent: re-running with the same arguments must not error if the branch already exists.
- This skill does not open a PR. It only sets up the branch and scope. Use `flowkit:pr` / `flowkit:open-pr` for sub-work.
