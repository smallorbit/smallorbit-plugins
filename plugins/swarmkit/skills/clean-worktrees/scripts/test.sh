#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for swarmkit:clean-worktrees scripts.
#
# Per the convention in plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 and emit a parseable JSON object on stdout
#   with the documented top-level keys.
# - Invalid-argument invocations exit non-zero and emit nothing on stdout.
#
# These scripts are network-free (operate on the local repo only) so a
# read-only happy path is exercised. `remove.sh` is invoked with empty input
# arrays so it has nothing to remove — a safe no-op.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

assert_invalid_args() {
  local script="$1"; shift
  local label="$1"; shift
  local stdout stderr rc
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  set +e
  "$SCRIPT_DIR/$script" "$@" >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e
  stdout="$(cat "$tmp_out")"
  stderr="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"

  if [[ $rc -eq 0 ]]; then
    red   "  FAIL [$script $label]: expected non-zero exit, got 0"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ -n "$stdout" ]]; then
    red   "  FAIL [$script $label]: expected empty stdout on invalid args, got:"
    printf '%s\n' "$stdout" | sed 's/^/         /'
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ -z "$stderr" ]]; then
    red   "  FAIL [$script $label]: expected non-empty stderr message"
    FAIL=$((FAIL + 1))
    return
  fi
  green "  PASS [$script $label]: exit=$rc, stdout empty"
  PASS=$((PASS + 1))
}

assert_json_keys() {
  local script="$1"; shift
  local label="$1"; shift
  local expected_keys="$1"; shift
  local stdout rc stderr_content
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  set +e
  "$SCRIPT_DIR/$script" "$@" >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e
  stdout="$(cat "$tmp_out")"
  stderr_content="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"

  if [[ $rc -ne 0 ]]; then
    red   "  FAIL [$script $label]: expected exit 0, got $rc"
    [[ -n "$stderr_content" ]] && printf '%s\n' "$stderr_content" | sed 's/^/         stderr: /'
    FAIL=$((FAIL + 1))
    return
  fi
  if ! printf '%s' "$stdout" | jq -e . >/dev/null 2>&1; then
    red   "  FAIL [$script $label]: stdout is not valid JSON"
    printf '%s\n' "$stdout" | sed 's/^/         /'
    FAIL=$((FAIL + 1))
    return
  fi
  local missing=""
  for key in $expected_keys; do
    if ! printf '%s' "$stdout" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
      missing+=" $key"
    fi
  done
  if [[ -n "$missing" ]]; then
    red   "  FAIL [$script $label]: missing top-level keys:$missing"
    FAIL=$((FAIL + 1))
    return
  fi
  green "  PASS [$script $label]: exit=0, JSON valid, keys present"
  PASS=$((PASS + 1))
}

echo "clean-worktrees: smoke-testing scripts"
echo

# gather.sh — no args, read-only. Always succeeds in any git repo.
assert_json_keys gather.sh "happy-path" \
  "caller_branch main_worktree worktrees_to_remove branches_to_delete stuck"

# remove.sh — invalid arg shapes.
assert_invalid_args remove.sh "missing-required" --worktrees '[]' --branches '[]'
assert_invalid_args remove.sh "unknown-flag"     --bogus value
assert_invalid_args remove.sh "missing-value"    --main-worktree

# remove.sh — empty arrays = safe no-op happy path. We pass the current main
# worktree so the cd succeeds, and an empty caller-branch so the restore step
# is a no-op.
MAIN_WT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
assert_json_keys remove.sh "empty-arrays-noop" \
  "removed remove_errors pruned_branches branch_errors caller_branch_restored" \
  --main-worktree "$MAIN_WT" --caller-branch "" --worktrees '[]' --branches '[]'

echo
echo "clean-worktrees: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
