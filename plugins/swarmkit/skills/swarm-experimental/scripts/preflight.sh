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

BASE="develop"
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
if ! git ls-remote --exit-code origin "$BASE" >/dev/null 2>&1; then
  base_existed=false
  if ! git ls-remote --exit-code origin main >/dev/null 2>&1; then
    echo "preflight: base '$BASE' is missing on origin and 'main' does not exist to seed it from" >&2
    exit 1
  fi
  if ! git fetch origin main >/dev/null 2>&1 \
    || ! git push origin "refs/remotes/origin/main:refs/heads/$BASE" >/dev/null 2>&1; then
    echo "preflight: failed to create '$BASE' on origin from 'main'" >&2
    exit 1
  fi
  base_created=true
fi

gh_authenticated=true
if ! gh auth status >/dev/null 2>&1; then
  gh_authenticated=false
fi

repo=""
if [[ "$gh_authenticated" == "true" ]]; then
  if ! repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
    echo "preflight: 'gh repo view' failed despite authenticated session" >&2
    exit 1
  fi
fi

if [[ "$SCOPE_PR_BASE" -eq 1 ]]; then
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
