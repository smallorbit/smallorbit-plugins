# swarm: a single epic argument enables epic mode

## Status

Draft. Authored 2026-06-02. Carved out of the `skill-evals` proposal, where it was resolved as open question 1 — it alters swarm runbook behavior independently of the eval work, so it ships as its own change. The `skill-evals` L3 EPIC_MODE eval depends on this change landing.

## Problem

`swarm`'s epic-mode resolution disables epic mode whenever the run is one-shot with exactly one issue (`issue_count==1 → off`). The stated rationale is "a standalone issue, by definition, cannot form a stack that needs isolation from `main`."

That rationale is correct for a genuine standalone issue, but **wrong for an epic**. When the single argument is an epic, the gather step expands it into N child issues — which absolutely can form a stack and benefit from a feature branch. Because EPIC_MODE is computed *before* gather (from the raw argument count), `/swarm <epic#>` resolves to flat-to-`main` and dispatches all N children as independent PRs against `main`, with no feature branch and no `ship-epic` promotion.

This surfaced live during the #1053 swarm: the operator passed a single epic number, the literal rule resolved EPIC_MODE off, and the eight children landed as flat PRs to `main` instead of stacking under a `feature/audit-remediation-*` branch. The behavior was ambiguous enough to require reasoning it out mid-run — a tell that the rule does not capture intent.

## Approach

Refine the disabling condition so it distinguishes a **standalone (non-epic) issue** from an **epic that expands to children**:

- One-shot with exactly one argument that is a standalone, non-epic issue → epic mode **off** (unchanged).
- One-shot with exactly one argument that is an epic expanding to ≥2 child issues → epic mode **on**: cut `feature/<slug>-<n>` (slug derived from the epic, or its lowest-numbered child), stack the children under it, then `merge-stack` + `ship-epic` promote to `main`.
- `--base` and `--no-epic` continue to force epic mode off regardless.

Because epic membership is only known after expansion, the resolution must consult the epic/sub-issue check that `gather_issues.sh` already performs (the `is_epic` / `epics_expanded` signal) rather than deciding purely on raw argument count. The "compute before any setup work" ordering is preserved for every case except the single-argument case, which requires a cheap epic-membership probe first.

## Non-goals

- Changing multi-issue one-shot, loop mode, or label-filter behavior (all already resolve epic mode on by default).
- Changing how the epic branch is cut, pinned, or torn down (that is unchanged; this only changes *when* epic mode turns on).
- Changing `--no-epic` / `--base` overrides.
