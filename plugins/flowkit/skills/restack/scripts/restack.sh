#!/usr/bin/env bash
set -euo pipefail

# restack.sh — rebase the open descendant PRs of a parent onto its updated head.
#
# Usage (two modes, mutually exclusive):
#   restack.sh --pr <N>                           # recursive subtree (user-facing)
#   restack.sh --branch <head> --upstream <ref>  # single-branch (cross-plugin)
#   restack.sh                                    # auto-resolve PR for current branch
#
# Success: exit 0, bare JSON object on stdout.
# Failure: exit 1, human-readable stderr, empty stdout.
# Invalid args: exit 2, human-readable stderr, empty stdout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTACK_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$(dirname "$RESTACK_DIR")"
WITH_CLEAN_SH="$SKILLS_DIR/with-clean-workspace/scripts/with_clean_workspace.sh"

die()       { echo "restack: $*" >&2; exit 1; }
die_usage() { echo "restack: $*" >&2; exit 2; }

usage() {
  cat >&2 <<'EOF'
restack: usage:
  restack.sh --pr <N>                           # rebase subtree of PR N (recursive)
  restack.sh --branch <head> --upstream <ref>  # rebase single branch onto ref
  restack.sh                                    # auto-resolve PR for current branch
EOF
}

# ── Save original args before parsing (needed for re-invocation guard) ────────
ORIGINAL_ARGS=("$@")

# ── Arg parsing ───────────────────────────────────────────────────────────────
PR_NUM=""
BRANCH_ARG=""
UPSTREAM_ARG=""
EXTRA_POSITIONAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      [[ $# -ge 2 ]] || die_usage "--pr requires a value"
      PR_NUM="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || die_usage "--branch requires a value"
      BRANCH_ARG="$2"
      shift 2
      ;;
    --upstream)
      [[ $# -ge 2 ]] || die_usage "--upstream requires a value"
      UPSTREAM_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die_usage "unknown flag: $1"
      ;;
    *)
      EXTRA_POSITIONAL=$((EXTRA_POSITIONAL + 1))
      shift
      ;;
  esac
done

[[ $EXTRA_POSITIONAL -gt 0 ]] && die_usage "unexpected positional argument(s)"

[[ -n "$PR_NUM" && -n "$BRANCH_ARG" ]] && die_usage "--pr and --branch are mutually exclusive"

[[ -n "$UPSTREAM_ARG" && -z "$BRANCH_ARG" ]] && die_usage "--upstream requires --branch"

[[ -n "$BRANCH_ARG" && -z "$UPSTREAM_ARG" ]] && die_usage "--branch requires --upstream"

if [[ -n "$PR_NUM" && ! "$PR_NUM" =~ ^[0-9]+$ ]]; then
  die_usage "--pr must be a numeric PR number, got: $PR_NUM"
fi

[[ -n "$BRANCH_ARG" ]] && MODE="single-branch" || MODE="recursive"

# ── Dep checks ────────────────────────────────────────────────────────────────
for cmd in jq git gh; do
  command -v "$cmd" >/dev/null 2>&1 || die "required dependency '$cmd' not found on PATH"
done

[[ -f "$WITH_CLEAN_SH" ]] || die "expected with-clean-workspace at $WITH_CLEAN_SH (flowkit layout)"

# ── Dirty-workspace guard: re-invoke via with-clean-workspace once ────────────
if [[ "${_RESTACK_WCW:-0}" != "1" ]]; then
  exec "$WITH_CLEAN_SH" -- env _RESTACK_WCW=1 bash "$0" "${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# From here the workspace is clean (stash was applied if needed).
# ══════════════════════════════════════════════════════════════════════════════

ORIGINAL_HEAD=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "")

# Temp files for JSON accumulation (one JSON object per line)
TMP_DIR=$(mktemp -d)
TMP_SUCCEEDED="$TMP_DIR/succeeded"
TMP_FAILED="$TMP_DIR/failed"
TMP_SKIPPED="$TMP_DIR/skipped"
touch "$TMP_SUCCEEDED" "$TMP_FAILED" "$TMP_SKIPPED"

_restore_head() {
  if [[ -n "$ORIGINAL_HEAD" ]]; then
    git checkout "$ORIGINAL_HEAD" 2>/dev/null || {
      echo "restack: WARNING: could not restore HEAD to '$ORIGINAL_HEAD'; falling back to develop" >&2
      git checkout develop 2>/dev/null || true
    }
  fi
}

_cleanup() {
  _restore_head
  rm -rf "$TMP_DIR"
}
trap _cleanup EXIT

# ── JSON helpers ──────────────────────────────────────────────────────────────

_record_success() {
  local branch="$1" upstream="$2"
  jq -n --arg b "$branch" --arg u "$upstream" \
    '{branch:$b,upstream:$u,force_pushed:true}' >> "$TMP_SUCCEEDED"
}

_record_failure() {
  local branch="$1" upstream="$2" reason="$3"
  jq -n --arg b "$branch" --arg u "$upstream" --arg r "$reason" \
    '{branch:$b,upstream:$u,reason:$r}' >> "$TMP_FAILED"
}

_record_skipped() {
  local branch="$1" ancestor="$2"
  jq -n --arg b "$branch" --arg a "$ancestor" \
    '{branch:$b,reason:"ancestor-failed",ancestor:$a}' >> "$TMP_SKIPPED"
}

_emit_result() {
  local mode="$1" parent_json="$2"
  local succeeded_arr failed_arr skipped_arr
  succeeded_arr=$(jq -s '. // []' "$TMP_SUCCEEDED")
  failed_arr=$(jq -s '. // []' "$TMP_FAILED")
  skipped_arr=$(jq -s '. // []' "$TMP_SKIPPED")
  jq -n \
    --arg mode "$mode" \
    --argjson parent "$parent_json" \
    --argjson succeeded "$succeeded_arr" \
    --argjson failed "$failed_arr" \
    --argjson skipped "$skipped_arr" \
    --arg original_head "$ORIGINAL_HEAD" \
    '{mode:$mode,parent:$parent,succeeded:$succeeded,failed:$failed,skipped:$skipped,original_head:$original_head}'
}

_has_failures() {
  [[ $(jq -s '. // [] | length' "$TMP_FAILED") -gt 0 ]]
}

# ── Core: rebase one branch onto an upstream ref ──────────────────────────────
_rebase_single() {
  local branch="$1" upstream="$2"
  local upstream_short="${upstream#origin/}"

  git fetch origin "$branch" "${upstream_short}" 2>/dev/null || true

  if ! git ls-remote --heads origin "$branch" | grep -q "refs/heads/$branch"; then
    echo "restack: branch '$branch' not found on remote origin" >&2
    _record_failure "$branch" "$upstream" "branch-not-found"
    return 1
  fi

  git checkout "$branch"

  set +e
  git rebase "$upstream"
  local rebase_exit=$?
  set -e

  if [[ $rebase_exit -ne 0 ]]; then
    git rebase --abort 2>/dev/null || true
    echo "restack: rebase conflict on '$branch' onto '$upstream'" >&2
    _record_failure "$branch" "$upstream" "rebase-conflict"
    return 1
  fi

  set +e
  git push --force-with-lease origin "$branch"
  local push_exit=$?
  set -e

  if [[ $push_exit -ne 0 ]]; then
    echo "restack: force-push rejected for '$branch'" >&2
    _record_failure "$branch" "$upstream" "force-push-rejected"
    return 1
  fi

  _record_success "$branch" "$upstream"
  return 0
}

# ── BFS helpers ───────────────────────────────────────────────────────────────

_get_open_descendants() {
  local parent_branch="$1"
  gh pr list --base "$parent_branch" --state open --json headRefName \
    --jq '.[].headRefName' 2>/dev/null || true
}

_skip_subtree() {
  local root_branch="$1" ancestor="$2"
  local queue=("$root_branch")
  local qi=0
  while [[ $qi -lt ${#queue[@]} ]]; do
    local cur="${queue[$qi]}"
    qi=$((qi + 1))
    while IFS= read -r child; do
      [[ -z "$child" ]] && continue
      _record_skipped "$child" "$ancestor"
      queue+=("$child")
    done < <(_get_open_descendants "$cur")
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# SINGLE-BRANCH MODE
# ══════════════════════════════════════════════════════════════════════════════

if [[ "$MODE" == "single-branch" ]]; then
  _rebase_single "$BRANCH_ARG" "$UPSTREAM_ARG" || true
  _emit_result "single-branch" "null"
  _has_failures && exit 1
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# RECURSIVE MODE (--pr N or auto-resolve)
# ══════════════════════════════════════════════════════════════════════════════

if [[ -z "$PR_NUM" ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
    die "not on a named branch and no --pr given; cannot auto-resolve PR"
  fi
  PR_NUM=$(gh pr list --head "$CURRENT_BRANCH" --json number \
    --jq 'if length > 0 then .[0].number | tostring else empty end' 2>/dev/null || true)
  if [[ -z "$PR_NUM" ]]; then
    die "no open PR found for branch '$CURRENT_BRANCH'"
  fi
fi

PR_META=$(gh pr view "$PR_NUM" --json headRefName,number)
PARENT_HEAD=$(printf '%s' "$PR_META" | jq -r '.headRefName')
PARENT_PR_NUM=$(printf '%s' "$PR_META" | jq -r '.number')

if [[ -z "$PARENT_HEAD" || "$PARENT_HEAD" == "null" ]]; then
  die "could not read headRefName for PR #$PR_NUM"
fi

PARENT_JSON=$(jq -n --argjson n "$PARENT_PR_NUM" --arg h "$PARENT_HEAD" \
  '{pr_number:$n,head_branch:$h}')

# BFS queue: parallel arrays of (branch, upstream_ref)
declare -a Q_BRANCH=()
declare -a Q_UPSTREAM=()

while IFS= read -r child; do
  [[ -z "$child" ]] && continue
  Q_BRANCH+=("$child")
  Q_UPSTREAM+=("origin/$PARENT_HEAD")
done < <(_get_open_descendants "$PARENT_HEAD")

QI=0
while [[ $QI -lt ${#Q_BRANCH[@]} ]]; do
  CB="${Q_BRANCH[$QI]}"
  CU="${Q_UPSTREAM[$QI]}"
  QI=$((QI + 1))

  if _rebase_single "$CB" "$CU"; then
    while IFS= read -r grandchild; do
      [[ -z "$grandchild" ]] && continue
      Q_BRANCH+=("$grandchild")
      Q_UPSTREAM+=("origin/$CB")
    done < <(_get_open_descendants "$CB")
  else
    _skip_subtree "$CB" "$CB"
  fi
done

_emit_result "recursive" "$PARENT_JSON"
_has_failures && exit 1
exit 0
