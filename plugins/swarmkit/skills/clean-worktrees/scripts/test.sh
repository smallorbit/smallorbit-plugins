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

# gather.sh — path/branch decoupling test.
# Simulate swarm worktrees where path name (agent-<hex>) differs from branch name
# (worktree-agent-<n>). Build a scratch git repo with two registered worktrees
# whose paths and branches are intentionally mismatched, verify gather.sh:
#   - emits those worktrees in worktrees_to_remove
#   - emits the checked-out branches in branches_to_delete (not stuck)
#   - stuck is empty (the only checked-out branches are in the removal set)
echo "  [gather.sh path-branch-mismatch] setting up scratch repo..."
SCRATCH_DIR="$(mktemp -d)"
cleanup_scratch() { rm -rf "$SCRATCH_DIR"; }
trap cleanup_scratch EXIT

# Main repo.
MAIN_REPO="$SCRATCH_DIR/main"
git init -q "$MAIN_REPO"
git -C "$MAIN_REPO" commit -q --allow-empty -m "init"

# Create the worktree-agent-* branches in the main repo.
git -C "$MAIN_REPO" branch worktree-agent-694
git -C "$MAIN_REPO" branch worktree-agent-695

# Create two agent worktrees with hex-style paths but issue-numbered branches.
WT1="$SCRATCH_DIR/main/.claude/worktrees/agent-a08bdd74112e06062"
WT2="$SCRATCH_DIR/main/.claude/worktrees/agent-b19cee85223f17173"
mkdir -p "$(dirname "$WT1")"
git -C "$MAIN_REPO" worktree add -q "$WT1" worktree-agent-694
git -C "$MAIN_REPO" worktree add -q "$WT2" worktree-agent-695

# Run gather.sh from within the main repo so git commands resolve correctly.
GATHER_OUT="$(cd "$MAIN_REPO" && bash "$SCRIPT_DIR/gather.sh" 2>/tmp/gather_stderr)"
GATHER_RC=$?

if [[ $GATHER_RC -ne 0 ]]; then
  red   "  FAIL [gather.sh path-branch-mismatch]: gather.sh exited $GATHER_RC"
  cat /tmp/gather_stderr | sed 's/^/         stderr: /' || true
  FAIL=$((FAIL + 1))
else
  # Verify worktrees_to_remove has 2 entries.
  WT_COUNT="$(printf '%s' "$GATHER_OUT" | jq '.worktrees_to_remove | length')"
  # Verify branches_to_delete contains both worktree-agent-694 and worktree-agent-695.
  B694="$(printf '%s' "$GATHER_OUT" | jq -r '.branches_to_delete[] | select(. == "worktree-agent-694")')"
  B695="$(printf '%s' "$GATHER_OUT" | jq -r '.branches_to_delete[] | select(. == "worktree-agent-695")')"
  # Verify stuck is empty.
  STUCK_COUNT="$(printf '%s' "$GATHER_OUT" | jq '.stuck | length')"

  if [[ "$WT_COUNT" -eq 2 && -n "$B694" && -n "$B695" && "$STUCK_COUNT" -eq 0 ]]; then
    green "  PASS [gather.sh path-branch-mismatch]: 2 worktrees to remove, branches in delete list, stuck empty"
    PASS=$((PASS + 1))
  else
    red   "  FAIL [gather.sh path-branch-mismatch]: unexpected output"
    printf '%s\n' "$GATHER_OUT" | jq . | sed 's/^/         /'
    FAIL=$((FAIL + 1))
  fi
fi

echo
echo "clean-worktrees: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
