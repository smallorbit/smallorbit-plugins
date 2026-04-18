#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // empty')

case "$SKILL" in
  flowkit:cut|flowkit:ship) ;;
  *) exit 0 ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

NEEDS_BUMP=()
for manifest in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$manifest" ] || continue
  name=$(jq -r '.name' "$manifest")
  current=$(jq -r '.version' "$manifest")
  plugin_dir=$(dirname "$(dirname "$manifest")")
  last_tag=$(git tag --list "${name}--v*" | sort -V | tail -1)
  [ -z "$last_tag" ] && continue
  tag_version="${last_tag#${name}--v}"
  if [ "$current" = "$tag_version" ]; then
    count=$(git log "${last_tag}..HEAD" --oneline -- "$plugin_dir/" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      NEEDS_BUMP+=("${name} (${count} commits since ${last_tag}, still at v${current})")
    fi
  fi
done

if [ ${#NEEDS_BUMP[@]} -eq 0 ]; then
  exit 0
fi

REASON="Plugin(s) have commits since last tag but no version bump:"$'\n'
for p in "${NEEDS_BUMP[@]}"; do
  REASON="${REASON}  - ${p}"$'\n'
done
REASON="${REASON}"$'\n'"Run /bump-versions first so clients pick up the updated code, then retry /${SKILL#flowkit:}."

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
