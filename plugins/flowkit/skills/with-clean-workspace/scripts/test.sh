#!/usr/bin/env bash
set -uo pipefail

# test.sh — deterministic behavior tests for flowkit:with-clean-workspace.
#
# These tests build throwaway git repositories to validate stash semantics for:
# - invalid usage
# - dirty-worktree success path (auto-stash + auto-pop)
# - dirty-worktree failure path (stash preserved + warning)
# - dirty-worktree pop-conflict path (warning + stash preserved)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

TMP_REPO=""

create_temp_repo() {
  TMP_REPO="$(mktemp -d)"
  cd "$TMP_REPO" || return 1
  git init -q
  git config user.name "with-clean-workspace-tests"
  git config user.email "tests@example.invalid"
  printf 'base\n' > tracked.txt
  git add tracked.txt
  git commit -qm "init"
}

cleanup_temp_repo() {
  local original_pwd="$1"
  cd "$original_pwd" || true
  if [[ -n "$TMP_REPO" ]]; then
    rm -rf "$TMP_REPO"
  fi
  TMP_REPO=""
}

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
  stdout="$(<"$tmp_out")"
  stderr="$(<"$tmp_err")"
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

test_dirty_success_pops_stash() {
  local rc stash_count tracked_contents untracked_restored
  local tmp_out tmp_err original_pwd
  original_pwd="$(pwd)"
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  if ! create_temp_repo; then
    red "  FAIL [dirty-success]: failed to create temp git repo"
    FAIL=$((FAIL + 1))
    rm -f "$tmp_out" "$tmp_err"
    return
  fi

  printf 'dirty change\n' > tracked.txt
  printf 'scratch\n' > untracked.txt

  set +e
  "$SCRIPT_DIR/with_clean_workspace.sh" -- bash -lc 'test -f tracked.txt && test ! -f untracked.txt' >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e

  git stash list >"$tmp_out"
  stash_count="$(wc -l < "$tmp_out" | tr -d ' ')"
  tracked_contents="$(<tracked.txt)"
  if [[ -f untracked.txt ]]; then
    untracked_restored="yes"
  else
    untracked_restored="no"
  fi
  cleanup_temp_repo "$original_pwd"
  rm -f "$tmp_out" "$tmp_err"

  if [[ $rc -ne 0 ]]; then
    red "  FAIL [dirty-success]: expected exit 0, got $rc"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$stash_count" -ne 0 ]]; then
    red "  FAIL [dirty-success]: expected empty stash after pop, found $stash_count entries"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$tracked_contents" != "dirty change" || "$untracked_restored" != "yes" ]]; then
    red "  FAIL [dirty-success]: expected tracked/untracked changes restored"
    FAIL=$((FAIL + 1))
    return
  fi
  green "  PASS [dirty-success]: stash popped and local changes restored"
  PASS=$((PASS + 1))
}

test_dirty_failure_preserves_stash() {
  local rc stderr stash_count
  local tmp_err tmp_out original_pwd
  original_pwd="$(pwd)"
  tmp_err="$(mktemp)"
  tmp_out="$(mktemp)"
  if ! create_temp_repo; then
    red "  FAIL [dirty-failure]: failed to create temp git repo"
    FAIL=$((FAIL + 1))
    rm -f "$tmp_out" "$tmp_err"
    return
  fi

  printf 'dirty change\n' > tracked.txt
  printf 'scratch\n' > untracked.txt

  set +e
  "$SCRIPT_DIR/with_clean_workspace.sh" -- bash -lc 'exit 7' >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e
  stderr="$(<"$tmp_err")"
  stash_count="$(git stash list | wc -l | tr -d ' ')"
  cleanup_temp_repo "$original_pwd"
  rm -f "$tmp_err" "$tmp_out"

  if [[ $rc -ne 7 ]]; then
    red "  FAIL [dirty-failure]: expected exit 7, got $rc"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$stash_count" -lt 1 ]]; then
    red "  FAIL [dirty-failure]: expected preserved stash entry"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$stderr" != *"wrapped command failed — stash preserved"* ]]; then
    red "  FAIL [dirty-failure]: expected preserved-stash warning on stderr"
    FAIL=$((FAIL + 1))
    return
  fi
  green "  PASS [dirty-failure]: non-zero exit preserved stash with warning"
  PASS=$((PASS + 1))
}

test_pop_conflict_preserves_stash() {
  local rc stderr stash_count tracked_contents
  local tmp_err tmp_out original_pwd
  original_pwd="$(pwd)"
  tmp_err="$(mktemp)"
  tmp_out="$(mktemp)"
  if ! create_temp_repo; then
    red "  FAIL [pop-conflict]: failed to create temp git repo"
    FAIL=$((FAIL + 1))
    rm -f "$tmp_out" "$tmp_err"
    return
  fi

  printf 'dirty change\n' > tracked.txt

  # Wrapped command edits the same path differently so stash pop cannot apply cleanly.
  set +e
  "$SCRIPT_DIR/with_clean_workspace.sh" -- bash -lc "printf 'wrapped change\n' > tracked.txt" >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e
  stderr="$(<"$tmp_err")"
  stash_count="$(git stash list | wc -l | tr -d ' ')"
  tracked_contents="$(<tracked.txt)"
  cleanup_temp_repo "$original_pwd"
  rm -f "$tmp_err" "$tmp_out"

  if [[ $rc -ne 0 ]]; then
    red "  FAIL [pop-conflict]: expected wrapped command exit 0, got $rc"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$stderr" != *"stash pop conflicted"* ]]; then
    red "  FAIL [pop-conflict]: expected conflict warning on stderr"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$stash_count" -lt 1 ]]; then
    red "  FAIL [pop-conflict]: expected stash entry to remain after conflict"
    FAIL=$((FAIL + 1))
    return
  fi
  if [[ "$tracked_contents" != "wrapped change" ]]; then
    red "  FAIL [pop-conflict]: expected wrapped command edits to remain in workspace"
    FAIL=$((FAIL + 1))
    return
  fi
  green "  PASS [pop-conflict]: warned and preserved stash on conflict"
  PASS=$((PASS + 1))
}

echo "with-clean-workspace: testing argument validation + stash behavior"
echo

assert_invalid_args with_clean_workspace.sh "missing-separator"
assert_invalid_args with_clean_workspace.sh "separator-only" --
assert_invalid_args with_clean_workspace.sh "unknown-flag" --help
test_dirty_success_pops_stash
test_dirty_failure_preserves_stash
test_pop_conflict_preserves_stash

echo
echo "with-clean-workspace: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
