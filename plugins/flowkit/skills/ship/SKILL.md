---
name: ship
description: Repo-level release closer that chains flowkit:cut → flowkit:release to promote develop to main. Aborts up front if any open worktree-agent-* PRs target the resolved base — operators land them via /swarmkit:merge-stack first so a verify gate can run against the integrated develop snapshot before ship.
triggers:
  - "/ship"
  - "ship the release"
  - "cut and release"
  - "promote develop to main"
allowed-tools: Bash
---

# Ship

Cut a release candidate from `develop` and ship it to `main` in one shot. Ship is the **release closer** — it does not merge open swarm PRs and does not promote epics to develop. Those steps belong to `/swarmkit:merge-stack` and `/flowkit:ship-epic` respectively, run by the operator beforehand so a verify gate can sit between integration and release.

## Input

`$ARGUMENTS` — optional notes passed through to `/release` as release context. If omitted, everything is auto-derived.

## Process

### 1. Preflight: refuse to ship while swarm PRs are open

Resolve the base branch and query for open `worktree-agent-*` PRs that target it:

```bash
BASE=$(git config --get claude.flowkit.prBase 2>/dev/null || echo "develop")

OPEN=$(gh pr list \
  --base "$BASE" \
  --state open \
  --json number,title,headRefName 2>/dev/null \
  | jq '[.[] | select(.headRefName | startswith("worktree-agent-"))]')

if [[ -n "$OPEN" && "$OPEN" != "[]" ]]; then
  echo "$OPEN" | jq -r '.[] | "  #\(.number) (\(.headRefName)): \(.title)"' >&2
  echo >&2
  echo "flowkit:ship: open swarm PRs detected against $BASE. Run /swarmkit:merge-stack to land them before shipping." >&2
  exit 1
fi
```

`gh pr list --head` is exact-match only — it does not support glob patterns, so the previous `--head 'worktree-agent-*'` filter silently returned an empty list and the abort guard never fired. Filtering the full open-PR set through `jq`'s `startswith` matches the intended prefix semantics.

The preflight is a hard gate. Open swarm PRs against the resolved base mean the integrated `develop` (or epic) state ship would package up does not yet include their work — releasing now would silently strand them. The operator clears this by running `/swarmkit:merge-stack` and (when an epic is in flight) `/flowkit:ship-epic` first, with a verify pass against the integrated state in between.

If `claude.flowkit.prBase` is set to a `feature/*` branch, that branch is the resolved base — the preflight catches stack PRs targeting the epic. After the operator runs `/flowkit:ship-epic` to promote the epic, the pin is unset and `BASE` falls through to `develop` on the next ship attempt.

### 2. Cut a release candidate

Invoke `flowkit:cut` via the Skill tool:

```
Skill({skill: "flowkit:cut"})
```

cut creates `rc/<YYYY-MM-DD>.N` from `origin/develop`, pushes it, and pushes the matching tag.

If cut fails (e.g., empty diff against main), stop and report.

### 3. Release

Invoke `flowkit:release` via the Skill tool:

```
Skill({skill: "flowkit:release", arguments: $ARGUMENTS})
```

Pass `$ARGUMENTS` (this skill's input) through to release as its release-notes hint.

release runs the rebase-merge preflight, opens the RC → main PR, rebase-merges, tags, runs the explicit `gh issue close` loop, and cleans up RC branches.

If release fails, stop and report.

### 4. Final report

Report:

- The RC branch created
- The release tag created on main
- Issues closed (aggregated from release's own report)

## Constraints

- Never commit directly to `develop` or `main`
- No branch/commit/PR creation outside what `cut` and `release` produce — those belong to `/pr` and `/swarm`
- The preflight is non-negotiable: do not bypass or weaken it. Open swarm PRs must be merged via `/swarmkit:merge-stack` (and the epic promoted via `/flowkit:ship-epic` when applicable) before ship runs
- No internal verify gate. Ship assumes the operator has already verified the integrated state against the project's tests between merge-stack and ship-epic (or between ship-epic and ship). Ship just packages what is already on `develop`
- Stop on any sub-skill failure. State is recoverable across partial failures: re-running `/ship` after the operator resolves the failure picks up where the chain left off
