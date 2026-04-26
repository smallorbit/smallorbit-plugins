#!/usr/bin/env bash
set -euo pipefail

emit_silent() {
  printf '{}\n'
  exit 0
}

command -v jq >/dev/null 2>&1 || emit_silent

shopt -s nullglob
configs=( "$HOME"/.claude/teams/*/config.json )
[ ${#configs[@]} -gt 0 ] || emit_silent

SID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SID" ]; then
  PROJECT_PATH="${PWD//\//-}"
  PROJECT_DIR="$HOME/.claude/projects/${PROJECT_PATH}"
  if [ -d "$PROJECT_DIR" ]; then
    latest=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1 || true)
    [ -n "$latest" ] && SID=$(basename "$latest" .jsonl)
  fi
fi

matched_role=""
matched_team=""

for cfg in "${configs[@]}"; do
  [ -r "$cfg" ] || continue

  role=$(jq -r --arg sid "$SID" --arg cwd "$PWD" '
    if ($sid != "" and .leadSessionId == $sid) then
      ((.members[]? | select(.agentType == "team-lead" or .agentType == "lead") | .agentType) // "team-lead")
    else
      ((.members[]? | select(.cwd == $cwd) | .agentType) // empty)
    end
  ' "$cfg" 2>/dev/null | head -1)

  if [ -n "$role" ] && [ "$role" != "null" ]; then
    matched_role="$role"
    matched_team=$(jq -r '.name // "unknown"' "$cfg")
    break
  fi
done

[ -n "$matched_role" ] || emit_silent

case "$matched_role" in
  lead) role_file="team-lead" ;;
  *) role_file="$matched_role" ;;
esac

project_override=".claude/agents/${role_file}.md"
plugin_path="plugins/squadkit/agents/${role_file}.md"

if [ -f "$project_override" ]; then
  resolved="$project_override"
else
  resolved="$plugin_path"
fi

message="Active squadkit team \`${matched_team}\` detected for this session (role: ${matched_role}). Load your role contract from \`${resolved}\` before continuing — prefer the project-local override at \`${project_override}\` if present, otherwise fall back to \`${plugin_path}\`."

jq -n --arg msg "$message" '{systemMessage: $msg}'
