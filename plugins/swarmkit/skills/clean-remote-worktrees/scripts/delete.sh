#!/usr/bin/env bash
set -euo pipefail

# delete.sh — batch-delete a list of remote branches in a single push call.
#
# Usage:
#   delete.sh --branches <json-array-of-branch-names>
#
# Only pass branches that are confirmed safe to delete (MERGED state).
# The caller is responsible for safety classification — this script deletes
# whatever it receives without further state checks.
#
# On success: exit 0, single JSON object on stdout with keys:
#   {deleted: [string], skipped: [{branch, reason}], errors: [string]}
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "delete: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

BRANCHES_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branches)
      [[ $# -ge 2 ]] || { echo "delete: --branches requires a value" >&2; exit 2; }
      BRANCHES_JSON="$2"; shift 2 ;;
    *)
      echo "delete: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$BRANCHES_JSON" ]] || { echo "delete: --branches is required" >&2; exit 2; }

T_PUSH_ERR=$(mktemp)
trap "rm -f $T_PUSH_ERR" EXIT

branch_count="$(printf '%s' "$BRANCHES_JSON" | jq 'length')"

if [[ "$branch_count" -eq 0 ]]; then
  jq -n '{deleted: [], skipped: [], errors: []}'
  exit 0
fi

refspecs=()
while IFS= read -r branch; do
  [[ -z "$branch" ]] && continue
  refspecs+=(":$branch")
done < <(printf '%s' "$BRANCHES_JSON" | jq -r '.[]')

deleted=()
errors=()

if git push origin "${refspecs[@]}" 2>"$T_PUSH_ERR"; then
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    deleted+=("$branch")
  done < <(printf '%s' "$BRANCHES_JSON" | jq -r '.[]')
else
  err="$(cat "$T_PUSH_ERR")"
  errors+=("$err")
fi

if [[ ${#deleted[@]} -gt 0 ]]; then
  deleted_json="$(printf '%s\n' "${deleted[@]}" | jq -R '.' | jq -s '.')"
else
  deleted_json="[]"
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  errors_json="$(printf '%s\n' "${errors[@]}" | jq -R '.' | jq -s '.')"
else
  errors_json="[]"
fi

jq -n \
  --argjson deleted "$deleted_json" \
  --argjson errors "$errors_json" \
  '{deleted: $deleted, skipped: [], errors: $errors}'
