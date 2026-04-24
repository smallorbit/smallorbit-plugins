#!/usr/bin/env bash
set -euo pipefail

# gather_issues.sh — collapse Step 1 (gather issue details) into one HTTP call.
#
# Batches title, body, labels, state, sub-issues, and native dependency edges
# for N issues into a single `gh api graphql` query using one alias per issue.
# Dependencies prefer GitHub's native `blockedBy` connection; falls back to
# parsing `Depends on #N` / `Blocked by #N` from the issue body when native is
# empty.
#
# Usage:
#   gather_issues.sh <number> [<number> ...]
#
# On success: exit 0, single JSON object on stdout:
#   {
#     "requested": [<number>, ...],
#     "work_items": [
#       {"number", "title", "body", "labels", "state", "is_epic",
#        "deps", "skip", "skip_reason", "source_epic"}
#     ],
#     "skipped":        [{"number", "reason"}, ...],
#     "epics_expanded": [{"number", "children": [<number>, ...]}, ...],
#     "epics_unwired":  [<number>, ...]
#   }
# On failure: non-zero exit, empty stdout, message on stderr.

if [[ $# -lt 1 ]]; then
  echo "gather_issues: at least one issue number is required" >&2
  exit 2
fi

for n in "$@"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "gather_issues: issue numbers must be positive integers (got '$n')" >&2
    exit 2
  fi
done

for cmd in gh jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "gather_issues: required dependency '$cmd' not found on PATH" >&2
    exit 1
  fi
done

if ! REPO_SLUG="$(gh repo view --json owner,name -q '.owner.login + "/" + .name' 2>/dev/null)"; then
  echo "gather_issues: 'gh repo view' failed — is this a gh-authenticated repo?" >&2
  exit 1
fi
OWNER="${REPO_SLUG%%/*}"
NAME="${REPO_SLUG##*/}"

REQUESTED_JSON="$(printf '%s\n' "$@" | jq -R 'tonumber' | jq -s '.')"

build_alias_block() {
  local n="$1"
  cat <<EOF
    i${n}: issue(number: ${n}) {
      number
      title
      body
      state
      labels(first: 50) { nodes { name } }
      subIssues(first: 100) {
        totalCount
        nodes {
          number
          title
          body
          state
          labels(first: 50) { nodes { name } }
          blockedBy(first: 50) { nodes { number } }
        }
      }
      blockedBy(first: 50) { nodes { number } }
    }
EOF
}

ALIAS_BLOCKS=""
for n in "$@"; do
  ALIAS_BLOCKS+="$(build_alias_block "$n")"$'\n'
done

QUERY=$(cat <<EOF
query(\$owner: String!, \$name: String!) {
  repository(owner: \$owner, name: \$name) {
${ALIAS_BLOCKS}
  }
}
EOF
)

if ! RAW="$(gh api graphql -F owner="$OWNER" -F name="$NAME" -f query="$QUERY" 2>/tmp/gather_issues.err)"; then
  echo "gather_issues: GraphQL query failed:" >&2
  cat /tmp/gather_issues.err >&2
  rm -f /tmp/gather_issues.err
  exit 1
fi
rm -f /tmp/gather_issues.err

if echo "$RAW" | jq -e '.errors' >/dev/null 2>&1; then
  echo "gather_issues: GraphQL returned errors:" >&2
  echo "$RAW" | jq -r '.errors[] | .message' >&2
  exit 1
fi

REPO_JSON="$(echo "$RAW" | jq '.data.repository')"

REQUESTED_ARG="$REQUESTED_JSON"

OUTPUT="$(jq -n \
  --argjson requested "$REQUESTED_ARG" \
  --argjson repo "$REPO_JSON" \
  '
  def parse_body_deps($body):
    ($body // "")
    | [ scan("(?i)(?:depends on|blocked by)\\s*#([0-9]+)") | .[0] | tonumber ]
    | unique;

  def resolve_deps(issue):
    (issue.blockedBy.nodes // [] | map(.number)) as $native
    | if ($native | length) > 0
      then $native
      else parse_body_deps(issue.body)
      end;

  def labels_of(issue):
    (issue.labels.nodes // []) | map(.name);

  def is_on_hold(issue):
    labels_of(issue) | any(. == "on-hold");

  def is_closed(issue):
    (issue.state // "OPEN") == "CLOSED";

  def has_epic_label(issue):
    labels_of(issue) | any(. == "epic");

  def work_item(issue; source_epic):
    {
      number: issue.number,
      title: issue.title,
      body: (issue.body // ""),
      labels: labels_of(issue),
      state: issue.state,
      is_epic: false,
      deps: resolve_deps(issue),
      skip: false,
      skip_reason: null,
      source_epic: source_epic
    };

  reduce $requested[] as $n (
    {work_items: [], skipped: [], epics_expanded: [], epics_unwired: []};
    ($repo["i" + ($n|tostring)]) as $iss
    | if $iss == null then
        .skipped += [{number: $n, reason: "issue not found"}]
      elif (is_on_hold($iss)) then
        .skipped += [{number: $n, reason: "on-hold label"}]
      elif (is_closed($iss)) then
        .skipped += [{number: $n, reason: "closed"}]
      elif (($iss.subIssues.totalCount // 0) > 0) then
        (
          ($iss.subIssues.nodes // [])
          | map(select((labels_of(.) | any(. == "on-hold") | not)
                       and ((.state // "OPEN") != "CLOSED")))
        ) as $active_children
        | .epics_expanded += [{number: $n, children: ($active_children | map(.number))}]
        | .work_items += ($active_children | map(work_item(.; $n)))
      elif (has_epic_label($iss)) then
        .epics_unwired += [$n]
      else
        .work_items += [work_item($iss; null)]
      end
  )
  | {requested: $requested} + .
  '
)"

echo "$OUTPUT"
