## Context

EPIC_MODE is currently computed from the raw argument shape, before `gather_issues.sh` runs:

```
if --base is set:                                  EPIC_MODE=off
elif --no-epic is set:                             EPIC_MODE=off
elif arg-mode == one-shot AND issue_count == 1:    EPIC_MODE=off
else:                                              EPIC_MODE=on
```

The third clause is the bug: `issue_count` is the count of *arguments*, so a single epic argument (which expands to N children) is treated like a standalone issue. `gather_issues.sh` already knows the difference — it returns `is_epic` per work-item and an `epics_expanded` list — but that signal arrives after EPIC_MODE is decided.

## Decision

Make the single-argument case epic-aware by probing epic membership before finalizing EPIC_MODE:

```
if --base is set:                                  EPIC_MODE=off
elif --no-epic is set:                             EPIC_MODE=off
elif one-shot AND single arg AND arg is an epic
     that expands to >=2 children:                 EPIC_MODE=on   # NEW
elif one-shot AND issue_count == 1:                EPIC_MODE=off  # standalone non-epic
else:                                              EPIC_MODE=on
```

The probe is cheap — the same epic/sub-issue check `gather_issues.sh` performs. Two implementation options:
1. Run `gather_issues.sh` for the single-arg case first, read `epics_expanded`, then finalize EPIC_MODE. (Reuses existing tooling; reorders gather before the cut for this one case.)
2. A minimal standalone epic-membership probe (label `epic` + has wired sub-issues) before the cut.

Option 1 is preferred — no new probe, and the gather output is needed anyway.

## Edge cases

- **Epic labeled but no sub-issues wired** → not a real expandable epic; `gather` already reports `epics_unwired` and skips. EPIC_MODE stays off (nothing to stack). Announce per the existing unwired-epic template.
- **Epic with exactly one wired child** → expands to one issue; treat as standalone, EPIC_MODE off (no stack to isolate). The `>=2 children` threshold encodes this.
- **`--no-epic` on a single epic arg** → still off; the override wins, children PR to `$BASE` directly.
- **`--base` on a single epic arg** → still off; explicit base wins.
- **Slug derivation** → reuse the existing multi-issue rule: derive from the epic (or its lowest-numbered child) via `gh issue view`.

## Verification

- Unit (L1): extend `swarm/scripts/test.sh` (or gather's test) to assert `epics_expanded`/`is_epic` is populated for a single epic arg fixture.
- Behavioral (L3, in `skill-evals`): assert `/swarm <epic#>` resolves EPIC_MODE on and cuts a `feature/` branch; assert a single standalone issue still resolves off.
