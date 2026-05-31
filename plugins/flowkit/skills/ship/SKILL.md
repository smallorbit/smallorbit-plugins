---
name: ship
description: Tag HEAD of main, push the tag, and create a GitHub Release. Single-command release for GitHub Flow — no release branch, no release PR. Derives a date-based calver tag (vYYYY.M.D[.N]) for calver repos, falling back to semver derived from conventional commits since the last v* tag.
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

### 2. Derive the next release tag

This repo's release tags are date-based calver (`vYYYY.M.D`, with a `.N` suffix for same-day re-releases, e.g. `v2026.5.29.2`), but the skill also supports plain semver (`vX.Y.Z`) repos. Detect the tag scheme from `$LAST_TAG` and branch — the calver path increments the date (and its same-day `.N` suffix), while the semver path keeps the conventional-commit bump arithmetic.

First scan conventional-commit messages since `$LAST_TAG` (or all of `main` if there is no prior tag). Pick the highest signal:

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

Decide the scheme. A repo is calver if `$LAST_TAG` is a calver tag, or — when there is no `$LAST_TAG` — if the repo's existing `v*` tags (excluding per-plugin `--v` tags) are calver. Otherwise it is semver.

```bash
CALVER_RE='^v[0-9]{4}\.[0-9]+\.[0-9]+(\.[0-9]+)?$'

if [ -n "$LAST_TAG" ]; then
  [[ "$LAST_TAG" =~ $CALVER_RE ]] && SCHEME="calver" || SCHEME="semver"
else
  # No prior tag: infer scheme from the newest existing release tag, if any
  PROBE_TAG=$(git tag --list 'v*' | grep -v -- '--v' | sort -V | tail -1)
  if [ -n "$PROBE_TAG" ] && [[ "$PROBE_TAG" =~ $CALVER_RE ]]; then
    SCHEME="calver"
  else
    SCHEME="semver"
  fi
fi
```

**Derive `NEXT_TAG`** with a single `if/elif/else` over `$SCHEME` so an unexpected value fails loudly instead of leaving `NEXT_TAG` unset (which would otherwise create an empty-named tag at `git tag -a`).

**Calver path** — the next tag is today's date, with a `.N` suffix when one or more releases already shipped today. The conventional-commit BUMP signal does not move a calver date, so it is ignored here.

```bash
if [ "$SCHEME" = "calver" ]; then
  TODAY="v$(date +%Y).$(date +%-m).$(date +%-d)"
  # Escape the dots in $TODAY — they are regex metacharacters in the grep below, so a tag
  # like v2026X5Y30 must not false-match the literal date v2026.5.30
  TODAY_ESC=$(printf '%s' "$TODAY" | sed 's/\./\\./g')
  # Highest existing tag for today, matching $TODAY or $TODAY.N (per-plugin --v tags excluded)
  HIGHEST_TODAY=$(git tag --list 'v*' | grep -v -- '--v' \
    | grep -E "^${TODAY_ESC}(\.[0-9]+)?$" | sort -V | tail -1)

  if [ -z "$HIGHEST_TODAY" ]; then
    NEXT_TAG="$TODAY"
  elif [ "$HIGHEST_TODAY" = "$TODAY" ]; then
    NEXT_TAG="${TODAY}.1"
  else
    SUFFIX="${HIGHEST_TODAY##*.}"
    NEXT_TAG="${TODAY}.$((SUFFIX + 1))"
  fi
  # The [ ... ] test exits 1 in the first-of-day case ($NEXT_TAG == $TODAY); || true keeps the
  # command substitution from aborting the run under set -e
  RATIONALE="calver release for $(date +%Y-%m-%d)$([ "$NEXT_TAG" != "$TODAY" ] && echo "; same-day .${NEXT_TAG##*.} increment" || true)"

# Semver path — first-ever release defaults to v0.1.0 (ignore the derived bump — there is
# no previous version to bump from). Otherwise increment the bumped component of $LAST_TAG.
elif [ "$SCHEME" = "semver" ]; then
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
else
  echo "ship: unknown tag scheme '$SCHEME' (expected 'calver' or 'semver')" >&2
  exit 1
fi
```

### 3. Confirm with the operator

Show the proposed tag and rationale, then ask the operator to confirm or override:

```
Proposed release tag: v2026.5.29.2
Rationale: calver release for 2026-05-29; same-day .2 increment
Commits since v2026.5.29.1:
  feat(swarmkit): add idle notification (#988)
  fix(flowkit): handle empty diff in commit skill (#989)
  chore(deps): bump gh CLI version (#990)

Proceed with v2026.5.29.2? (yes / override <tag> / no)
```

If the operator overrides, validate the override matches either the semver shape `^v[0-9]+\.[0-9]+\.[0-9]+$` or the calver shape `^v[0-9]{4}\.[0-9]+\.[0-9]+(\.[0-9]+)?$` (no pre-release suffixes — keep it simple) and use it instead. If they say "no" or abort, stop without mutating anything.

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
