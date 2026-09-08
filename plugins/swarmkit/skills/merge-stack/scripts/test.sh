#!/usr/bin/env bash
set -uo pipefail

# test.sh — smoke tests for swarmkit:merge-stack scripts.
#
# Per the convention in plugins/_shared/script-authoring.md:
# - Successful invocations exit 0 and emit a parseable JSON object on stdout
#   with the documented top-level keys.
# - Invalid-argument invocations exit non-zero and emit nothing on stdout.
#
# select_prs.sh normally sources the open-PR list from `gh pr list`. Its
# `--pr-json <file>` input replaces that one network call with a fixture, so the
# whole selection algebra (layer resolution, set arithmetic, validation,
# dedupe, classification) is exercised offline. No test here touches the
# network or mutates repository state.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

FIXTURE_DIR="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE_DIR"; }
trap cleanup EXIT

PRS="$FIXTURE_DIR/prs.json"
cat >"$PRS" <<'JSON'
[
  {"number": 103, "title": "swarm root",        "headRefName": "worktree-agent-103", "baseRefName": "main"},
  {"number": 104, "title": "swarm mid",         "headRefName": "worktree-agent-104", "baseRefName": "worktree-agent-103"},
  {"number": 105, "title": "swarm leaf",        "headRefName": "worktree-agent-105", "baseRefName": "worktree-agent-104"},
  {"number": 108, "title": "swarm independent", "headRefName": "worktree-agent-108", "baseRefName": "main"},
  {"number": 120, "title": "ad-hoc root",       "headRefName": "fix/typo",           "baseRefName": "main"},
  {"number": 134, "title": "ad-hoc child",      "headRefName": "fix/other",          "baseRefName": "fix/typo"},
  {"number": 150, "title": "epic root",         "headRefName": "chore/deps",         "baseRefName": "feature/epic-9"},
  {"number": 151, "title": "epic child",        "headRefName": "chore/deps-2",       "baseRefName": "chore/deps"}
]
JSON

cat >"$FIXTURE_DIR/no-swarm.json" <<'JSON'
[
  {"number": 120, "title": "ad-hoc root", "headRefName": "fix/typo", "baseRefName": "main"}
]
JSON

NOT_JSON="$FIXTURE_DIR/not-an-array.json"
printf '{"number": 1}\n' >"$NOT_JSON"

run_script() {
  RUN_STDOUT=""; RUN_STDERR=""; RUN_RC=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  bash "$SCRIPT_DIR/select_prs.sh" "$@" >"$tmp_out" 2>"$tmp_err"
  RUN_RC=$?
  RUN_STDOUT="$(cat "$tmp_out")"
  RUN_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

assert_fails() {
  local label="$1"; shift
  local want_rc="$1"; shift
  run_script "$@"
  if [[ $RUN_RC -ne $want_rc ]]; then
    red "  FAIL [select_prs.sh $label]: expected exit $want_rc, got $RUN_RC"
    FAIL=$((FAIL + 1)); return
  fi
  if [[ -n "$RUN_STDOUT" ]]; then
    red "  FAIL [select_prs.sh $label]: expected empty stdout, got:"
    printf '%s\n' "$RUN_STDOUT" | sed 's/^/         /'
    FAIL=$((FAIL + 1)); return
  fi
  if [[ -z "$RUN_STDERR" ]]; then
    red "  FAIL [select_prs.sh $label]: expected non-empty stderr message"
    FAIL=$((FAIL + 1)); return
  fi
  green "  PASS [select_prs.sh $label]: exit=$RUN_RC, stdout empty"
  PASS=$((PASS + 1))
}

# assert_selection <label> <jq-filter-expecting-true> -- <args...>
assert_selection() {
  local label="$1"; shift
  local filter="$1"; shift
  [[ "$1" == "--" ]] && shift
  run_script "$@"
  if [[ $RUN_RC -ne 0 ]]; then
    red "  FAIL [select_prs.sh $label]: expected exit 0, got $RUN_RC"
    [[ -n "$RUN_STDERR" ]] && printf '%s\n' "$RUN_STDERR" | sed 's/^/         stderr: /'
    FAIL=$((FAIL + 1)); return
  fi
  if ! printf '%s' "$RUN_STDOUT" | jq -e . >/dev/null 2>&1; then
    red "  FAIL [select_prs.sh $label]: stdout is not valid JSON"
    printf '%s\n' "$RUN_STDOUT" | sed 's/^/         /'
    FAIL=$((FAIL + 1)); return
  fi
  local missing=""
  local key
  for key in selection_mode base base_pinned base_candidates count pr_numbers prs \
             merge_set_branches swarm_branches non_swarm_prs pure_swarm requires_confirmation; do
    if ! printf '%s' "$RUN_STDOUT" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
      missing+=" $key"
    fi
  done
  if [[ -n "$missing" ]]; then
    red "  FAIL [select_prs.sh $label]: missing top-level keys:$missing"
    FAIL=$((FAIL + 1)); return
  fi
  if ! printf '%s' "$RUN_STDOUT" | jq -e "$filter" >/dev/null 2>&1; then
    red "  FAIL [select_prs.sh $label]: assertion failed: $filter"
    printf '%s\n' "$RUN_STDOUT" | jq . | sed 's/^/         /'
    FAIL=$((FAIL + 1)); return
  fi
  green "  PASS [select_prs.sh $label]: exit=0, JSON valid, assertion held"
  PASS=$((PASS + 1))
}

echo "merge-stack: smoke-testing scripts"
echo

# --- Invalid arguments ---------------------------------------------------
assert_fails "unknown-flag"           2 --bogus --pr-json "$PRS"
assert_fails "non-numeric-positional" 2 "fix/typo" --pr-json "$PRS"
assert_fails "base-missing-value"     2 --base --pr-json "$PRS"
assert_fails "include-no-numbers"     2 --include --pr-json "$PRS"
assert_fails "pr-json-missing-value"  2 --pr-json
assert_fails "mutual-exclusion"       2 --base main 120 --pr-json "$PRS"
assert_fails "mutual-exclusion-order" 2 120 --base main --pr-json "$PRS"

# --- Runtime failures ----------------------------------------------------
assert_fails "unknown-positional-pr"  1 999 --pr-json "$PRS"
assert_fails "unknown-include-pr"     1 --include 999 --pr-json "$PRS"
assert_fails "pr-json-not-found"      1 --pr-json "$FIXTURE_DIR/missing.json"
assert_fails "pr-json-not-an-array"   1 --pr-json "$NOT_JSON"

# --- Default (swarm) set -------------------------------------------------
assert_selection "default-swarm-set" '
  .selection_mode == "default"
  and .pr_numbers == [103, 104, 105, 108]
  and .base == "main"
  and .base_pinned == false
  and .pure_swarm == true
  and .requires_confirmation == false
  and .non_swarm_prs == []
  and (.swarm_branches | length) == 4
' -- --pr-json "$PRS"

assert_selection "default-empty-when-no-swarm-prs" '
  .count == 0 and .pr_numbers == [] and .pure_swarm == true
  and .requires_confirmation == false and .base == null
' -- --pr-json "$FIXTURE_DIR/no-swarm.json"

# --- Positionals replace the default ------------------------------------
assert_selection "positionals-replace" '
  .selection_mode == "exact"
  and .pr_numbers == [120, 134]
  and (.swarm_branches | length) == 0
  and .non_swarm_prs == [120, 134]
  and .pure_swarm == false
  and .requires_confirmation == true
  and .base == "main"
  and .base_pinned == false
' -- 120 134 --pr-json "$PRS"

assert_selection "positionals-multi-root-base-yields-null-base" '
  .selection_mode == "exact"
  and .pr_numbers == [103, 150]
  and .count == 2
  and .base == null
  and .base_pinned == false
  and .base_candidates == ["feature/epic-9", "main"]
' -- 103 150 --pr-json "$PRS"

assert_selection "positionals-hash-prefix-accepted" '
  .pr_numbers == [120]
' -- "#120" --pr-json "$PRS"

assert_selection "positionals-pure-swarm-subset" '
  .selection_mode == "exact" and .pr_numbers == [103, 104]
  and .pure_swarm == true and .requires_confirmation == false
' -- 103 104 --pr-json "$PRS"

# --- --include extends the current base set ------------------------------
assert_selection "include-extends-default" '
  .selection_mode == "default"
  and .pr_numbers == [103, 104, 105, 108, 120]
  and .non_swarm_prs == [120]
  and .pure_swarm == false
  and .requires_confirmation == true
' -- --include 120 --pr-json "$PRS"

assert_selection "include-extends-positionals" '
  .selection_mode == "exact" and .pr_numbers == [103, 120]
' -- 103 --include 120 --pr-json "$PRS"

assert_selection "include-extends-base-scope" '
  .selection_mode == "base"
  and .base == "feature/epic-9"
  and .base_pinned == true
  and .pr_numbers == [108, 150, 151]
' -- --base feature/epic-9 --include 108 --pr-json "$PRS"

# --- --base scopes by topology and pins the retarget target --------------
assert_selection "base-scopes-and-pins" '
  .selection_mode == "base"
  and .base == "feature/epic-9"
  and .base_pinned == true
  and .pr_numbers == [150, 151]
  and .pure_swarm == false
' -- --base feature/epic-9 --pr-json "$PRS"

assert_selection "base-transitive-closure" '
  .selection_mode == "base"
  and .base == "main"
  and .base_pinned == true
  and .pr_numbers == [103, 104, 105, 108, 120, 134]
' -- --base main --pr-json "$PRS"

assert_selection "base-unknown-branch-selects-nothing" '
  .count == 0 and .base == "feature/nope" and .base_pinned == true
' -- --base feature/nope --pr-json "$PRS"

# --- Dedupe --------------------------------------------------------------
assert_selection "dedupe-positionals-and-include" '
  .pr_numbers == [120, 134] and .count == 2
' -- 120 120 134 --include 120 134 --pr-json "$PRS"

assert_selection "dedupe-include-against-default-set" '
  .pr_numbers == [103, 104, 105, 108] and .count == 4 and .pure_swarm == true
' -- --include 103 108 --pr-json "$PRS"

echo
echo "merge-stack: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
