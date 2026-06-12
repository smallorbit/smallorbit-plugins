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

# teardown.sh — accepts --base <value>, --keep-pr-base (no value).
assert_invalid_args teardown.sh "unknown-flag"              --not-a-flag
assert_invalid_args teardown.sh "missing-value"             --base
assert_invalid_args teardown.sh "keep-pr-base-extra-positional" --keep-pr-base extra-positional

# verify_agent.sh — exactly one positive integer.
assert_invalid_args verify_agent.sh "no-args"
assert_invalid_args verify_agent.sh "non-integer"   not-a-number
assert_invalid_args verify_agent.sh "negative"      -5
assert_invalid_args verify_agent.sh "extra-args"    1 2

# gather_issues.sh — at least one positive-integer arg.
assert_invalid_args gather_issues.sh "no-args"
assert_invalid_args gather_issues.sh "non-integer"  abc
assert_invalid_args gather_issues.sh "mixed-bad"    1 abc

echo "swarm: DEFAULT_BRANCH empty-string guard"
echo

# preflight.sh: gh returns empty defaultBranchRef → guard falls back to "main"
# Stubs: gh returns empty string (exit 0); git fetch succeeds; rev-parse fails
# for the custom base branch but succeeds for "main"; jq and git push are not
# reached because the test asserts on the error path.
(
  stub_dir="$(mktemp -d)"
  trap 'rm -rf "$stub_dir"' EXIT

  cat >"$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
# Simulate: gh repo view returns empty defaultBranchRef; auth check fails so
# the authenticated block is skipped; "gh repo view" for nameWithOwner is also
# not exercised on this path.
if [[ "$*" == *"defaultBranchRef"* ]]; then
  printf ''
  exit 0
fi
# auth status — report unauthenticated so the gh_authenticated block is skipped
exit 1
STUB
  chmod +x "$stub_dir/gh"

  cat >"$stub_dir/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "fetch" ]]; then exit 0; fi
if [[ "$1" == "rev-parse" ]]; then
  # Fail for "refs/remotes/origin/nonexistent-base" (the custom --base value),
  # succeed for "refs/remotes/origin/main" (the guard fallback).
  if [[ "$*" == *"nonexistent-base"* ]]; then exit 1; fi
  if [[ "$*" == *"refs/remotes/origin/main"* ]]; then exit 1; fi
  exit 1
fi
if [[ "$1" == "config" ]]; then exit 0; fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$stub_dir/git"

  # jq must be real; only gh and git are stubbed
  PATH="$stub_dir:$PATH" \
    tmp_out="$(mktemp)" tmp_err="$(mktemp)" rc=0
  set +e
  PATH="$stub_dir:$PATH" "$SCRIPT_DIR/preflight.sh" --base nonexistent-base \
    >"$tmp_out" 2>"$tmp_err"
  rc=$?
  set -e
  stderr_out="$(cat "$tmp_err")"
  stdout_out="$(cat "$tmp_out")"
  rm -f "$tmp_out" "$tmp_err"

  if [[ $rc -eq 0 ]]; then
    red   "  FAIL [preflight.sh empty-gh-result]: expected non-zero exit, got 0"
    FAIL=$((FAIL + 1))
  elif [[ -n "$stdout_out" ]]; then
    red   "  FAIL [preflight.sh empty-gh-result]: expected empty stdout, got: $stdout_out"
    FAIL=$((FAIL + 1))
  elif [[ "$stderr_out" == *"''"* ]] || [[ "$stderr_out" != *"main"* ]]; then
    red   "  FAIL [preflight.sh empty-gh-result]: error message should reference 'main', got: $stderr_out"
    FAIL=$((FAIL + 1))
  else
    green "  PASS [preflight.sh empty-gh-result]: exit=$rc, stderr references 'main'"
    PASS=$((PASS + 1))
  fi
)

echo
echo "swarm: gather_issues epic-expansion contract (stubbed gh)"
echo

# These back the single-epic-argument EPIC_MODE resolution: gather must expose
# epics_expanded/work_items so the skill can tell an expandable epic from a
# standalone issue. Network-free — gh is stubbed with canned GraphQL responses.
gstub="$(mktemp -d)"
cat >"$gstub/canned-epic.json" <<'JSON'
{"data":{"repository":{"i42":{"number":42,"title":"epic: thing","body":"","state":"OPEN","labels":{"nodes":[{"name":"epic"}]},"subIssues":{"totalCount":2,"nodes":[{"number":101,"title":"a","body":"","state":"OPEN","labels":{"nodes":[]},"blockedBy":{"nodes":[]}},{"number":102,"title":"b","body":"","state":"OPEN","labels":{"nodes":[]},"blockedBy":{"nodes":[{"number":101}]}}]},"blockedBy":{"nodes":[]}}}}}
JSON
cat >"$gstub/canned-standalone.json" <<'JSON'
{"data":{"repository":{"i12":{"number":12,"title":"standalone","body":"","state":"OPEN","labels":{"nodes":[]},"subIssues":{"totalCount":0,"nodes":[]},"blockedBy":{"nodes":[]}}}}}
JSON
cat >"$gstub/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then printf 'octo/repo\n'; exit 0; fi
if [[ "$1" == "api" && "$2" == "graphql" ]]; then cat "$GATHER_STUB_CANNED"; exit 0; fi
exit 1
STUB
chmod +x "$gstub/gh"

# Single epic argument #42 → expands to two wired children (EPIC_MODE=on path).
out="$(GATHER_STUB_CANNED="$gstub/canned-epic.json" PATH="$gstub:$PATH" "$SCRIPT_DIR/gather_issues.sh" 42 2>/dev/null)"; rc=$?
children="$(printf '%s' "$out" | jq -c '.epics_expanded[0].children' 2>/dev/null)"
n_items="$(printf '%s' "$out" | jq '.work_items | length' 2>/dev/null)"
src="$(printf '%s' "$out" | jq -c '[.work_items[].source_epic] | unique' 2>/dev/null)"
if [[ $rc -eq 0 && "$children" == "[101,102]" && "$n_items" == "2" && "$src" == "[42]" ]]; then
  green "  PASS [gather_issues single-epic-arg]: #42 expands → children [101,102], 2 work_items, source_epic 42"
  PASS=$((PASS + 1))
else
  red   "  FAIL [gather_issues single-epic-arg]: rc=$rc children=$children items=$n_items src=$src"
  FAIL=$((FAIL + 1))
fi

# Standalone issue #12 → not an epic, no expansion (EPIC_MODE=off path).
out="$(GATHER_STUB_CANNED="$gstub/canned-standalone.json" PATH="$gstub:$PATH" "$SCRIPT_DIR/gather_issues.sh" 12 2>/dev/null)"; rc=$?
n_exp="$(printf '%s' "$out" | jq '.epics_expanded | length' 2>/dev/null)"
n_items="$(printf '%s' "$out" | jq '.work_items | length' 2>/dev/null)"
num="$(printf '%s' "$out" | jq '.work_items[0].number' 2>/dev/null)"
src="$(printf '%s' "$out" | jq '.work_items[0].source_epic' 2>/dev/null)"
if [[ $rc -eq 0 && "$n_exp" == "0" && "$n_items" == "1" && "$num" == "12" && "$src" == "null" ]]; then
  green "  PASS [gather_issues standalone-issue]: #12 flat, no epic expansion"
  PASS=$((PASS + 1))
else
  red   "  FAIL [gather_issues standalone-issue]: rc=$rc epics=$n_exp items=$n_items num=$num src=$src"
  FAIL=$((FAIL + 1))
fi
rm -rf "$gstub"

echo
echo "swarm: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
