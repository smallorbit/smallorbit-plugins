#!/usr/bin/env bash
set -euo pipefail

# select_prs.sh — resolve the merge set for swarmkit:merge-stack.
#
# Usage:
#   select_prs.sh [<pr>...] [--base <branch>] [--include <pr>...] [--pr-json <file>]
#
# Selection layers (the resolved set is always exactly one base layer, optionally
# extended by --include):
#   (none)            swarm default — open PRs whose head branch starts with
#                     `worktree-agent-`
#   <pr>...           exact set — replaces the swarm default
#   --base <branch>   stack scope — every open PR reachable from <branch> through
#                     base-relationship topology; replaces the swarm default and
#                     pins <branch> as the retarget target
#   --include <pr>... extends whichever base layer is in effect
#
# --base and positional PR numbers are mutually exclusive.
#
# --pr-json <file> reads the open-PR list from a JSON array on disk instead of
# querying `gh`. Used by the smoke tests and for offline dry runs; operators do
# not pass it.
#
# On success: exit 0, single JSON object on stdout with keys:
#   {selection_mode, base, base_pinned, base_candidates, count, pr_numbers,
#    prs: [{number, title, headRefName, baseRefName, is_swarm}],
#    merge_set_branches, swarm_branches, non_swarm_prs, pure_swarm,
#    requires_confirmation}
# On failure: non-zero exit (2 for invalid arguments, 1 for runtime failures),
# empty stdout, human-readable message on stderr.

SWARM_PREFIX="worktree-agent-"

usage_error() {
  echo "select-prs: $1" >&2
  exit 2
}

runtime_error() {
  echo "select-prs: $1" >&2
  exit 1
}

is_pr_number() { [[ "$1" =~ ^#?[0-9]+$ ]]; }

base_flag=""
base_given=false
pr_json_file=""
positionals=()
includes=()

args=("$@")
argc=${#args[@]}
idx=0
while (( idx < argc )); do
  arg="${args[$idx]}"
  case "$arg" in
    --base)
      (( idx + 1 < argc )) || usage_error "--base requires a branch name"
      base_flag="${args[$((idx + 1))]}"
      [[ -n "$base_flag" && "$base_flag" != --* ]] || usage_error "--base requires a branch name"
      base_given=true
      idx=$((idx + 2))
      ;;
    --include)
      idx=$((idx + 1))
      consumed=0
      while (( idx < argc )) && is_pr_number "${args[$idx]}"; do
        includes+=("${args[$idx]#\#}")
        consumed=$((consumed + 1))
        idx=$((idx + 1))
      done
      (( consumed > 0 )) || usage_error "--include requires at least one PR number"
      ;;
    --pr-json)
      (( idx + 1 < argc )) || usage_error "--pr-json requires a file path"
      pr_json_file="${args[$((idx + 1))]}"
      [[ -n "$pr_json_file" && "$pr_json_file" != --* ]] || usage_error "--pr-json requires a file path"
      idx=$((idx + 2))
      ;;
    --*)
      usage_error "unknown flag: $arg"
      ;;
    *)
      is_pr_number "$arg" || usage_error "positional arguments must be PR numbers, got: $arg"
      positionals+=("${arg#\#}")
      idx=$((idx + 1))
      ;;
  esac
done

if [[ "$base_given" == true && ${#positionals[@]} -gt 0 ]]; then
  usage_error "--base and positional PR numbers are mutually exclusive — pass one or the other"
fi

if ! command -v jq >/dev/null 2>&1; then
  runtime_error "required dependency 'jq' not found on PATH"
fi

if [[ -n "$pr_json_file" ]]; then
  [[ -f "$pr_json_file" ]] || runtime_error "--pr-json file not found: $pr_json_file"
  all_prs="$(cat "$pr_json_file")"
  if ! printf '%s' "$all_prs" | jq -e 'type == "array"' >/dev/null 2>&1; then
    runtime_error "--pr-json file must contain a JSON array: $pr_json_file"
  fi
else
  if ! command -v gh >/dev/null 2>&1; then
    runtime_error "required dependency 'gh' not found on PATH"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    runtime_error "gh is not authenticated — run 'gh auth login' first"
  fi
  if ! all_prs="$(gh pr list --state open --limit 500 --json number,title,headRefName,baseRefName 2>&1)"; then
    printf 'select-prs: gh pr list failed: %s\n' "$all_prs" >&2
    exit 1
  fi
fi

_number_array() {
  if [[ $# -eq 0 ]]; then
    echo '[]'
  else
    printf '%s\n' "$@" | jq -R 'tonumber' | jq -s 'unique'
  fi
}

positionals_json="$(_number_array "${positionals[@]+"${positionals[@]}"}")"
includes_json="$(_number_array "${includes[@]+"${includes[@]}"}")"

explicit_json="$(jq -n --argjson p "$positionals_json" --argjson i "$includes_json" '$p + $i | unique')"
missing="$(printf '%s' "$all_prs" \
  | jq -r --argjson explicit "$explicit_json" '($explicit - [.[].number]) | map(tostring) | join(", ")')"
if [[ -n "$missing" ]]; then
  runtime_error "PR(s) not found among open PRs: $missing"
fi

if [[ "$base_given" == true ]]; then
  mode="base"
elif [[ ${#positionals[@]} -gt 0 ]]; then
  mode="exact"
else
  mode="default"
fi

printf '%s' "$all_prs" | jq \
  --arg mode "$mode" \
  --arg base_flag "$base_flag" \
  --arg swarm_prefix "$SWARM_PREFIX" \
  --argjson positionals "$positionals_json" \
  --argjson includes "$includes_json" '
  def is_swarm($prefix): .headRefName | startswith($prefix);
  def member($set): . as $x | $set | index($x) != null;

  def expand($prs):
    . as $sel
    | ([$prs[] | select(.number | member($sel)) | .headRefName]) as $heads
    | ($sel + [$prs[] | select(.baseRefName | member($heads)) | .number] | unique);

  . as $prs
  | (
      if $mode == "exact" then
        $positionals
      elif $mode == "base" then
        reduce range(0; ($prs | length)) as $_
          ([$prs[] | select(.baseRefName == $base_flag) | .number]; expand($prs))
      else
        [$prs[] | select(is_swarm($swarm_prefix)) | .number]
      end
    ) as $base_set
  | ($base_set + $includes | unique) as $selected_numbers
  | ([$prs[] | select(.number | member($selected_numbers))] | sort_by(.number)) as $sel
  | ([$sel[].headRefName]) as $sel_heads
  | ([$sel[] | select(.baseRefName | member($sel_heads) | not) | .baseRefName] | unique) as $root_bases
  | ([$sel[] | select(is_swarm($swarm_prefix) | not) | .number]) as $non_swarm
  | (($non_swarm | length) == 0) as $pure_swarm
  | {
      selection_mode: $mode,
      base: (
        if $mode == "base" then $base_flag
        elif ($root_bases | length) == 1 then $root_bases[0]
        else null
        end
      ),
      base_pinned: ($mode == "base"),
      base_candidates: $root_bases,
      count: ($sel | length),
      pr_numbers: [$sel[].number],
      prs: [$sel[] | {number, title, headRefName, baseRefName, is_swarm: is_swarm($swarm_prefix)}],
      merge_set_branches: [$sel[].headRefName],
      swarm_branches: [$sel[] | select(is_swarm($swarm_prefix)) | .headRefName],
      non_swarm_prs: $non_swarm,
      pure_swarm: $pure_swarm,
      requires_confirmation: ($pure_swarm | not)
    }
'
