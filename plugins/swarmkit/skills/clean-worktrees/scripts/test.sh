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

# gather.sh — stuck-from-outside test.
# A worktree at a path that does NOT match worktrees/(agent-|worktree-agent-)
# checks out a worktree-agent-* branch. That branch must land in stuck[], not
# branches_to_delete. An agent-path worktree on a different worktree-agent-*
# branch must land in branches_to_delete and worktrees_to_remove.
echo "  [gather.sh stuck-from-outside] setting up scratch repo..."
SCRATCH2_DIR="$(mktemp -d)"
cleanup_scratch2() { rm -rf "$SCRATCH2_DIR"; }
trap cleanup_scratch2 EXIT

MAIN2_REPO="$SCRATCH2_DIR/main"
git init -q "$MAIN2_REPO"
git -C "$MAIN2_REPO" commit -q --allow-empty -m "init"

git -C "$MAIN2_REPO" branch worktree-agent-700
git -C "$MAIN2_REPO" branch worktree-agent-701

# Agent-path worktree (will land in worktrees_to_remove + branches_to_delete).
AGENT_WT="$SCRATCH2_DIR/main/.claude/worktrees/agent-c30dff96334b28284"
mkdir -p "$(dirname "$AGENT_WT")"
git -C "$MAIN2_REPO" worktree add -q "$AGENT_WT" worktree-agent-700

# External-path worktree (NOT an agent path — checks out worktree-agent-701).
EXTERNAL_WT="$SCRATCH2_DIR/main/external-wt"
git -C "$MAIN2_REPO" worktree add -q "$EXTERNAL_WT" worktree-agent-701

GATHER2_OUT="$(cd "$MAIN2_REPO" && bash "$SCRIPT_DIR/gather.sh" 2>/tmp/gather2_stderr)"
GATHER2_RC=$?

if [[ $GATHER2_RC -ne 0 ]]; then
  red   "  FAIL [gather.sh stuck-from-outside]: gather.sh exited $GATHER2_RC"
  sed 's/^/         stderr: /' /tmp/gather2_stderr || true
  FAIL=$((FAIL + 1))
else
  WT2_COUNT="$(printf '%s' "$GATHER2_OUT" | jq '.worktrees_to_remove | length')"
  B700="$(printf '%s' "$GATHER2_OUT" | jq -r '.branches_to_delete[] | select(. == "worktree-agent-700")')"
  B701_IN_DELETE="$(printf '%s' "$GATHER2_OUT" | jq -r '.branches_to_delete[] | select(. == "worktree-agent-701")')"
  B701_IN_STUCK="$(printf '%s' "$GATHER2_OUT" | jq -r '.stuck[].branch | select(. == "worktree-agent-701")')"
  STUCK2_COUNT="$(printf '%s' "$GATHER2_OUT" | jq '.stuck | length')"

  if [[ "$WT2_COUNT" -eq 1 && -n "$B700" && -z "$B701_IN_DELETE" && -n "$B701_IN_STUCK" && "$STUCK2_COUNT" -eq 1 ]]; then
    green "  PASS [gather.sh stuck-from-outside]: agent worktree in remove set, external worktree-agent branch in stuck"
    PASS=$((PASS + 1))
  else
    red   "  FAIL [gather.sh stuck-from-outside]: unexpected output"
    printf '%s\n' "$GATHER2_OUT" | jq . | sed 's/^/         /'
    FAIL=$((FAIL + 1))
  fi
fi

# gather.sh — caller_branch anchor test (regression for #844).
# Run gather.sh with CWD inside an agent worktree on a different branch and
# verify that caller_branch reflects the main worktree's checked-out branch,
# not the agent worktree's. Without the repo-root anchor in gather.sh, this
# would silently return the agent's branch.
echo "  [gather.sh anchor-from-agent-cwd] setting up scratch repo..."
SCRATCH3_DIR="$(mktemp -d)"
cleanup_scratch3() { rm -rf "$SCRATCH3_DIR"; }
trap cleanup_scratch3 EXIT

MAIN3_REPO="$SCRATCH3_DIR/main"
git init -q -b main-branch "$MAIN3_REPO"
git -C "$MAIN3_REPO" commit -q --allow-empty -m "init"

git -C "$MAIN3_REPO" branch worktree-agent-810
AGENT3_WT="$SCRATCH3_DIR/main/.claude/worktrees/agent-d41eff07445c39395"
mkdir -p "$(dirname "$AGENT3_WT")"
git -C "$MAIN3_REPO" worktree add -q "$AGENT3_WT" worktree-agent-810

# Run gather.sh from inside the agent worktree CWD. The anchor in gather.sh
# should redirect git operations to the main repo before reading the branch.
GATHER3_OUT="$(cd "$AGENT3_WT" && bash "$SCRIPT_DIR/gather.sh" 2>/tmp/gather3_stderr)"
GATHER3_RC=$?

if [[ $GATHER3_RC -ne 0 ]]; then
  red   "  FAIL [gather.sh anchor-from-agent-cwd]: gather.sh exited $GATHER3_RC"
  sed 's/^/         stderr: /' /tmp/gather3_stderr || true
  FAIL=$((FAIL + 1))
else
  CALLER_BRANCH="$(printf '%s' "$GATHER3_OUT" | jq -r '.caller_branch')"
  if [[ "$CALLER_BRANCH" == "main-branch" ]]; then
    green "  PASS [gather.sh anchor-from-agent-cwd]: caller_branch=main-branch (anchor held)"
    PASS=$((PASS + 1))
  else
    red   "  FAIL [gather.sh anchor-from-agent-cwd]: expected caller_branch=main-branch, got '$CALLER_BRANCH'"
    printf '%s\n' "$GATHER3_OUT" | jq . | sed 's/^/         /'
    FAIL=$((FAIL + 1))
  fi
fi

echo
echo "clean-worktrees: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
