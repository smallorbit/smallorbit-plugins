#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for flowkit:restack scripts.
#
# Per plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 with parseable JSON on stdout.
# - Invalid-argument invocations exit non-zero with empty stdout.
#
# restack.sh requires git, gh, and live GitHub state for happy paths.
# This harness covers argument-validation contracts only.

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
  green "  PASS [$script $label]: exit=$rc, stdout empty, stderr non-empty"
  PASS=$((PASS + 1))
}

echo "restack: smoke-testing argument validation contracts"
echo

assert_invalid_args restack.sh "non-numeric-pr"        --pr abc
assert_invalid_args restack.sh "pr-and-branch-mutex"   --pr 1 --branch foo
assert_invalid_args restack.sh "branch-without-upstream" --branch foo
assert_invalid_args restack.sh "upstream-without-branch" --upstream main
assert_invalid_args restack.sh "unknown-flag"          --unknown-flag
assert_invalid_args restack.sh "extra-positional"      extra-arg

echo
echo "restack: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
