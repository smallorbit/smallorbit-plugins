#!/usr/bin/env bash
set -euo pipefail

# detect_changed.sh — enumerate plugins with commits since their last per-plugin
# git tag and emit a bare-payload JSON array of changed-plugin records.
#
# Usage:
#   detect_changed.sh
#
# On success: exit 0, JSON array on stdout:
#   [{"plugin": "swarmkit", "last_tag": "swarmkit--v5.1.0", "commit_count": 3, "current_version": "5.1.0"}, ...]
#   Only plugins with commit_count > 0 (or no prior tag) are included.
# On failure: non-zero exit, empty stdout, human-readable message on stderr.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "detect_changed: must be run inside a git repository" >&2
  exit 1
}

for cmd in git jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "detect_changed: required dependency '$cmd' not found on PATH" >&2
    exit 1
  }
done

find "$REPO_ROOT/plugins" -maxdepth 3 -name "plugin.json" -path "*/.claude-plugin/plugin.json" | sort | while read -r manifest; do
  plugin_dir="$(dirname "$(dirname "$manifest")")"
  plugin_name="$(basename "$plugin_dir")"

  current_version="$(jq -r '.version // empty' "$manifest" 2>/dev/null)"
  if [[ -z "$current_version" ]]; then
    echo "detect_changed: could not read version from $manifest" >&2
    continue
  fi

  last_tag="$(git tag --list "${plugin_name}--v*" | sort -V | tail -1)"

  if [[ -z "$last_tag" ]]; then
    commit_count="$(git log --oneline -- "$plugin_dir/" 2>/dev/null | wc -l | tr -d ' ')"
    last_tag="(none)"
  else
    commit_count="$(git log --oneline "${last_tag}..HEAD" -- "$plugin_dir/" 2>/dev/null | wc -l | tr -d ' ')"
  fi

  if [[ "$commit_count" -gt 0 ]]; then
    jq -n \
      --arg plugin "$plugin_name" \
      --arg last_tag "$last_tag" \
      --argjson commit_count "$commit_count" \
      --arg current_version "$current_version" \
      '{"plugin": $plugin, "last_tag": $last_tag, "commit_count": $commit_count, "current_version": $current_version}'
  fi
done | jq -s '.'
