#!/usr/bin/env bash
set -euo pipefail

# test-all-skill-scripts.sh — discover and run every skill's `scripts/test.sh`
# smoke test across the monorepo. Single entry point for CI and manual runs.
#
# Usage:
#   scripts/test-all-skill-scripts.sh
#
# Discovery: walks `plugins/*/skills/*/scripts/test.sh`. Each test.sh is run
# with its own directory as CWD. A non-zero exit from any test.sh fails the
# whole runner, but every test is still attempted so the report is complete.
#
# Exit codes:
#   0  — all discovered tests passed
#   1  — at least one test failed
#   2  — no tests discovered

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for cmd in bash jq find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "test-all-skill-scripts: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

TESTS=()
while IFS= read -r line; do
  TESTS+=("$line")
done < <(find plugins -path 'plugins/*/skills/*/scripts/test.sh' -type f | sort)

if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "test-all-skill-scripts: no skill smoke tests discovered under plugins/*/skills/*/scripts/test.sh" >&2
  exit 2
fi

passed=0
failed=0
failed_paths=()

echo "Discovered ${#TESTS[@]} skill smoke test(s)."
echo

for test_path in "${TESTS[@]}"; do
  rel="${test_path#$REPO_ROOT/}"
  echo "==> $rel"
  test_dir="$(dirname "$test_path")"
  if ( cd "$test_dir" && bash "./test.sh" ); then
    passed=$((passed + 1))
    echo "    PASS"
  else
    failed=$((failed + 1))
    failed_paths+=("$rel")
    echo "    FAIL"
  fi
  echo
done

echo "------------------------------------------------------------"
echo "Skill smoke tests: ${passed} passed, ${failed} failed (of ${#TESTS[@]})"

if [[ $failed -gt 0 ]]; then
  echo
  echo "Failed tests:"
  for p in "${failed_paths[@]}"; do
    echo "  - $p"
  done
  exit 1
fi

exit 0
