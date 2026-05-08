#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for flowkit:push-or-pr scripts.
#
# Per the convention in plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 and emit a parseable JSON object on stdout.
# - Invalid-argument invocations exit non-zero and emit nothing on stdout.
#
# Happy paths for push_or_pr.sh require a live git remote, branch-protection
# rules, and `gh` auth. They cannot run from a smoke harness, so this file
# covers the deterministic argument-validation surface only. End-to-end
# behavior is exercised by the calling skills (bump-versions, release) when
# they run against the live repo.

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

echo "push-or-pr: smoke-testing argument validation contracts"
echo

# push_or_pr.sh — accepts --prefix, --title, --body, --base, all with values.
assert_invalid_args push_or_pr.sh "unknown-flag"          --not-a-flag
assert_invalid_args push_or_pr.sh "missing-prefix-value"  --prefix
assert_invalid_args push_or_pr.sh "missing-title-value"   --title
assert_invalid_args push_or_pr.sh "missing-body-value"    --body
assert_invalid_args push_or_pr.sh "missing-base-value"    --base
assert_invalid_args push_or_pr.sh "extra-positional"      positional-not-allowed

echo
echo "push-or-pr: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
