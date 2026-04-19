---
name: kits
description: Report which sibling kits are installed (version, scope, skills) and which metakit scenarios are currently runnable. Accepts an optional kit-name argument to drill into a single kit.
---

# Kits

Discovery command that shows which sibling kits are present in the current environment and which metakit scenarios they enable.

## Inputs

An optional kit-name argument passed by the user (e.g. `/kits speckit`). When provided, output is scoped to that kit only.

## Process

### 1. Call detect-kits

Run the `detect-kits` sub-skill. This returns a detection map keyed by kit name, where each present kit carries `version`, `scope`, and `skills`.

Store the result as `detectionMap`. If the argument was provided, restrict further rendering to that kit.

### 2. Render the kits table

If a kit-name argument was provided and the kit is absent from `detectionMap`, print:

```
`<kit-name>` is not installed in this environment.
```

and stop.

Otherwise render one row per kit in the canonical list (`speckit`, `swarmkit`, `polishkit`, `flowkit`, `sessionkit`, `vaultkit`):

- **Kit** — kit name
- **Version** — semver from detection map, or `—` if not installed
- **Scope** — `user` / `project` from detection map, or `—` if not installed
- **Skills** — comma-separated list of skill names, or `—` if not installed
- **Status** — `installed` if the kit is in `detectionMap`, otherwise `not installed`

When a kit-name argument was provided, render only the row for that kit.

Example output:

```
| Kit        | Version | Scope   | Skills                               | Status        |
|------------|---------|---------|--------------------------------------|---------------|
| speckit    | 1.2.7   | user    | spec, catalog, issue, interview      | installed     |
| swarmkit   | 2.4.1   | project | swarm, pick-issue, merge-stack, ...  | installed     |
| polishkit  | —       | —       | —                                    | not installed |
| flowkit    | 2.0.0   | user    | pr, commit, release, stage           | installed     |
| sessionkit | 1.1.0   | user    | handoff, pickup, skillit             | installed     |
| vaultkit   | —       | —       | —                                    | not installed |
```

Skip the scenarios section entirely when a kit-name argument was provided — the drill-down mode is kit-scoped, not scenario-scoped.

### 3. Render the scenarios section

Below the table, print a `## Scenarios` heading followed by a row for each metakit scenario. Evaluate each scenario against `detectionMap` using the required-kits definitions below.

**Scenario definitions**

| Scenario | Required kits |
|----------|---------------|
| `/polish-cycle` | `polishkit`, `speckit`, `swarmkit` |
| `/handoff-cycle` | `sessionkit` |

**Status rules** — apply in order:

1. If every required kit is present → `full`
2. If at least one required kit is present but one or more are missing → `partial (missing: <kit>, <kit>)`
3. If no required kit is present → `unavailable`

Example output:

```
## Scenarios

| Scenario         | Status                                |
|------------------|---------------------------------------|
| /polish-cycle    | partial (missing: polishkit, swarmkit)|
| /handoff-cycle   | full                                  |
```

## Notes

- This skill is read-only — it never modifies environment state.
- Skill lists in the table may be long; truncate with `...` after the first five names if there are more than five.
- The canonical kit list is: `speckit`, `swarmkit`, `polishkit`, `flowkit`, `sessionkit`, `vaultkit`. Kits outside this list are not reported even if they appear in the detection map.
