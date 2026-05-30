---
name: ship
description: Tag HEAD of main, push the tag, and create a GitHub Release. Single-command release for GitHub Flow — no release branch, no release PR. Derives the next semver from conventional commits since the last v* tag.
triggers:
  - "/ship"
  - "ship the release"
  - "tag and release"
  - "cut a release"
allowed-tools: Bash
---

# Ship

Tag HEAD of `main` and publish a GitHub Release. One command, one tag, one release page. Under GitHub Flow there is no release branch and no release PR — every PR has already been squash-merged into `main`, so the release is whatever's on `main` right now.

## Input

`$ARGUMENTS` — ignored. The release notes come from `gh release create --generate-notes`; the tag rationale is derived from the conventional-commit messages on `main` since the last `v*` tag.

## Process

### 0. Preflight migration check

If the repository is set up for the legacy v3 develop/RC/main flow, refuse to run and direct the operator at `/flowkit:migrate-v4`:

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
DEVELOP_EXISTS=$(git ls-remote --heads origin develop | grep -c 'refs/heads/develop' || true)
MAIN_EXISTS=$(git ls-remote --heads origin main | grep -c 'refs/heads/main' || true)

if [ "$DEFAULT_BRANCH" = "develop" ] || { [ "$DEVELOP_EXISTS" -gt 0 ] && [ "$MAIN_EXISTS" -eq 0 ]; }; then
  echo "This repo is set up for flowkit v3 (develop/main split). Run \`/flowkit:migrate-v4\` to migrate to single-trunk before using v4 skills." >&2
  exit 1
fi
```

### 1. Preflight: main, in sync, clean, progress

Refuse to run unless all four hold:

```bash
# Current branch must be main
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" != "main" ]; then
  echo "ship: must run on main (currently on $CURRENT). Run 'git checkout main' first." >&2
  exit 1
fi

# Local main must match origin/main exactly
git fetch origin main
LOCAL=$(git rev-parse main)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" != "$REMOTE" ]; then
  echo "ship: local main is not in sync with origin/main. Run /flowkit:sync first." >&2
  exit 1
fi

# Working tree must be clean
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ship: working tree is dirty. Commit or stash before shipping." >&2
  exit 1
fi

# At least one commit since the last v* tag (or no prior tag at all)
# grep -v '--v' excludes per-plugin tags (e.g. vaultkit--v1.1.8) that otherwise leak into the v* glob
LAST_TAG=$(git tag --list 'v*' | grep -v -- '--v' | sort -V | tail -1)
if [ -n "$LAST_TAG" ]; then
  COMMITS_SINCE=$(git rev-list --count "${LAST_TAG}..HEAD")
  if [ "$COMMITS_SINCE" -eq 0 ]; then
    echo "ship: no commits on main since $LAST_TAG. Nothing to release." >&2
    exit 1
  fi
fi
```

### 2. Derive the next semver

Scan conventional-commit messages since `$LAST_TAG` (or all of `main` if there is no prior tag). Pick the highest signal:

- Any `BREAKING CHANGE:` token in a commit body, or any `!:` after the type (e.g. `feat!:`, `fix!:`) → **major** bump
- Otherwise any `feat` type → **minor** bump
- Otherwise → **patch** bump

```bash
if [ -n "$LAST_TAG" ]; then
  RANGE="${LAST_TAG}..HEAD"
else
  RANGE="HEAD"
fi

COMMITS=$(git log "$RANGE" --pretty=format:'%B%n---COMMIT-BOUNDARY---')

BUMP="patch"
if printf '%s\n' "$COMMITS" | grep -qE '(BREAKING CHANGE:|^[a-z]+(\([^)]+\))?!:)'; then
  BUMP="major"
elif printf '%s\n' "$COMMITS" | grep -qE '^feat(\([^)]+\))?:'; then
  BUMP="minor"
fi
```

If there is no prior `v*` tag, the first-ever release defaults to `v0.1.0` (ignore the derived bump — there is no previous version to bump from).

Otherwise compute the next tag by incrementing the bumped component of `$LAST_TAG`:

```bash
if [ -z "$LAST_TAG" ]; then
  NEXT_TAG="v0.1.0"
  RATIONALE="first release"
else
  # Strip leading 'v' and split into MAJOR.MINOR.PATCH
  VERSION="${LAST_TAG#v}"
  MAJOR="${VERSION%%.*}"
  REST="${VERSION#*.}"
  MINOR="${REST%%.*}"
  PATCH="${REST#*.}"

  case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
  NEXT_TAG="v${MAJOR}.${MINOR}.${PATCH}"
  RATIONALE="$BUMP bump from $LAST_TAG (derived from conventional commits in $RANGE)"
fi
```

### 3. Confirm with the operator

Show the proposed tag and rationale, then ask the operator to confirm or override:

```
Proposed release tag: v1.4.0
Rationale: minor bump from v1.3.2 (derived from conventional commits in v1.3.2..HEAD)
Commits since v1.3.2:
  feat(swarmkit): add idle notification (#988)
  fix(flowkit): handle empty diff in commit skill (#989)
  chore(deps): bump gh CLI version (#990)

Proceed with v1.4.0? (yes / override <vX.Y.Z> / no)
```

If the operator overrides, validate the override matches `^v[0-9]+\.[0-9]+\.[0-9]+$` (no pre-release suffixes — keep it simple) and use it instead. If they say "no" or abort, stop without mutating anything.

### 4. Create and push the annotated tag

```bash
git tag -a "$NEXT_TAG" -m "Release $NEXT_TAG"
git push origin "$NEXT_TAG"
```

Annotated (`-a`) is required so the tag carries author and message metadata — lightweight tags do not.

### 5. Create the GitHub Release

```bash
gh release create "$NEXT_TAG" --generate-notes --title "$NEXT_TAG"
```

`--generate-notes` produces a release page listing the commits/PRs since the previous tag. No manual changelog editing required.

### 6. Report

Print:

- The new tag (`$NEXT_TAG`)
- The bump type and rationale
- The Release URL returned by `gh release create`

## Constraints

- The preflight is a hard gate — do not bypass any of the four conditions (on main, in sync, clean tree, commits since last tag) except for the first-ever-release exemption on the progress check
- The tag MUST be annotated (`git tag -a`); lightweight tags lose author metadata and break `git describe` heuristics
- Operator confirmation is non-negotiable — never push a tag without explicit operator approval
- This skill replaces the v3 `cut → release → ship` chain. There is no RC branch, no release PR, no `gh issue close` loop — squash-merged PRs already carried `Closes #N` footers which GitHub honored at merge time
