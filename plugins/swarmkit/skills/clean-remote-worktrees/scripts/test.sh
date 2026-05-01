#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for swarmkit:clean-remote-worktrees scripts.
#
# Per the convention in plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 and emit a parseable JSON object on stdout
#   with the documented top-level keys.
# - Invalid-argument invocations exit non-zero and emit nothing on stdout.
#
# classify.sh requires network access (git fetch + gh API) so only the
# invalid-argument surface is exercisable here. Since classify.sh accepts no
# flags, there is no flag-based invalid-arg path to test; the entire happy
# path is network-dependent and therefore deferred to CI.
#
# delete.sh has a network-free early-exit path (--branches '[]') that is
# exercised as the happy-path noop test.

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

echo "clean-remote-worktrees: smoke-testing scripts"
echo

# delete.sh — invalid arg shapes.
assert_invalid_args delete.sh "missing-required"  # no --branches at all
assert_invalid_args delete.sh "missing-value"     --branches
assert_invalid_args delete.sh "unknown-flag"      --bogus value

# delete.sh — empty array = network-free noop happy path.
assert_json_keys delete.sh "empty-array-noop" \
  "deleted skipped errors" \
  --branches '[]'

echo
echo "clean-remote-worktrees: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
