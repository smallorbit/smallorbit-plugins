#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for swarmkit:swarm scripts.
#
# Per the convention in plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 and emit a parseable JSON object on stdout
#   with the documented top-level keys.
# - Invalid-argument invocations exit non-zero and emit nothing on stdout.
#
# These tests focus on the deterministic, network-free contract surface:
# argument validation. Happy-path invocations for swarm scripts require live
# `gh` auth and `git fetch origin`, which are unsuitable for a smoke harness;
# that surface is exercised manually and via the skill itself.

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

echo "swarm: smoke-testing argument validation contracts"
echo

# preflight.sh — accepts --base <value>, --scope-pr-base, no positional.
assert_invalid_args preflight.sh "unknown-flag"      --not-a-flag
assert_invalid_args preflight.sh "missing-value"     --base
assert_invalid_args preflight.sh "extra-positional"  positional-not-allowed

# teardown.sh — accepts --base <value>.
assert_invalid_args teardown.sh "unknown-flag"   --not-a-flag
assert_invalid_args teardown.sh "missing-value"  --base

# verify_agent.sh — exactly one positive integer.
assert_invalid_args verify_agent.sh "no-args"
assert_invalid_args verify_agent.sh "non-integer"   not-a-number
assert_invalid_args verify_agent.sh "negative"      -5
assert_invalid_args verify_agent.sh "extra-args"    1 2

# gather_issues.sh — at least one positive-integer arg.
assert_invalid_args gather_issues.sh "no-args"
assert_invalid_args gather_issues.sh "non-integer"  abc
assert_invalid_args gather_issues.sh "mixed-bad"    1 abc

echo
echo "swarm: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
