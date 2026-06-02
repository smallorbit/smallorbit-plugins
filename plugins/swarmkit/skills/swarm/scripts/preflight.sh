#!/usr/bin/env bash
set -euo pipefail

# preflight.sh — collapse the swarm setup phase (fetch + base verification +
# gh auth check + optional PR base scoping) into one call.
#
# Usage:
#   preflight.sh [--base <branch>] [--scope-pr-base]
#
# On success: exit 0, single JSON object on stdout with keys:
#   {base, base_existed, base_created, gh_authenticated, repo}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

# Anchor to the main repo root. The harness can drop the operator's shell into
# an agent worktree between swarm runs; `git config --local` would otherwise
# write to the wrong worktree's config.
cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" || exit 1

BASE="main"
SCOPE_PR_BASE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || { echo "preflight: --base requires a value" >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    --scope-pr-base)
      SCOPE_PR_BASE=1
      shift
      ;;
    *)
      echo "preflight: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

for cmd in gh jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "preflight: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if ! git fetch origin >/dev/null 2>&1; then
  echo "preflight: 'git fetch origin' failed" >&2
  exit 1
fi

base_existed=true
base_created=false
if ! git rev-parse --verify --quiet "refs/remotes/origin/$BASE" >/dev/null; then
  base_existed=false
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
  DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
  if ! git rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH" >/dev/null; then
    echo "preflight: base '$BASE' is missing on origin and '$DEFAULT_BRANCH' does not exist to seed it from" >&2
    exit 1
  fi
  if ! git push origin "refs/remotes/origin/$DEFAULT_BRANCH:refs/heads/$BASE" >/dev/null 2>&1; then
    echo "preflight: failed to create '$BASE' on origin from '$DEFAULT_BRANCH'" >&2
    exit 1
  fi
  base_created=true
fi

gh_authenticated=false
repo=""
if gh auth status >/dev/null 2>&1; then
  gh_authenticated=true
  if ! repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
    echo "preflight: 'gh repo view' failed despite authenticated session" >&2
    exit 1
  fi
fi

if [[ "$SCOPE_PR_BASE" -eq 1 ]]; then
  # Cross-pin defensive guard — runs alongside the durable write so any direct
  # caller of `preflight --scope-pr-base` is protected, not just the SKILL prose.
  # Refuse to overwrite an existing epic pin that differs from the branch about
  # to be pinned.
  existing_pin="$(git config --local --get claude.flowkit.prBase 2>/dev/null || true)"
  if [[ -n "$existing_pin" && "$existing_pin" == feature/* && "$existing_pin" != "$BASE" ]]; then
    echo "swarm: an epic is already pinned (\`$existing_pin\`); pass \`--no-epic\` to swarm against main, or \`--epic <existing-slug>\` to reuse the pinned branch." >&2
    exit 1
  fi
  if ! git config --local claude.flowkit.prBase "$BASE" >/dev/null 2>&1; then
    echo "preflight: failed to set claude.flowkit.prBase via 'git config --local'" >&2
    exit 1
  fi
fi

jq -n \
  --arg base "$BASE" \
  --argjson base_existed "$base_existed" \
  --argjson base_created "$base_created" \
  --argjson gh_authenticated "$gh_authenticated" \
  --arg repo "$repo" \
  '{base: $base, base_existed: $base_existed, base_created: $base_created, gh_authenticated: $gh_authenticated, repo: $repo}'
