---
name: polish-cycle
description: Run a full quality loop across polishkit, speckit, and swarmkit — critique the code, catalog findings as GitHub issues, then swarm parallel agents to resolve them. Detects which sibling kits are installed and degrades gracefully when any are missing. Use when the user asks to "run a polish cycle", "do a quality pass", or "critique and fix" a codebase. Invoke as `/polish-cycle`.
---

# Polish Cycle

End-to-end quality loop that orchestrates three sibling kits:

1. **polishkit:critique** — produce a code-quality report (low-risk, runs automatically)
2. **speckit:catalog** — file the report's findings as GitHub issues (risky, pause for confirm)
3. **swarmkit:swarm** — spawn parallel agents to resolve the newly-filed issues (risky, pause for confirm)

Following the metakit contract: detect → preview → execute with pauses on risky steps → halt-and-report on failure.

## Prerequisites

- **polishkit must be installed.** Without it, there is nothing to critique — the scenario is unavailable. Report it and stop.
- **speckit and swarmkit are optional.** If either is missing, the corresponding step is skipped; the user is told which downstream steps cannot run.

## Process

### 1. Detect installed kits

Invoke the `detect-kits` sub-skill via the Skill tool. Capture the returned detection map.

### 2. Gate on polishkit

If `detectionMap["polishkit"]` is falsy:

```
Scenario unavailable: /polish-cycle requires polishkit (for the /critique step) and
it is not installed in this environment. Install polishkit and re-run.
```

Stop. Do not continue to plan-preview.

### 3. Build the scenario and render the plan

Compose the ordered step list:

```json
[
  { "stepName": "critique codebase",          "owningKit": "polishkit", "riskLevel": "safe" },
  { "stepName": "catalog findings as issues",  "owningKit": "speckit",   "riskLevel": "risky" },
  { "stepName": "swarm issues in parallel",    "owningKit": "swarmkit",  "riskLevel": "risky" }
]
```

Invoke the `plan-preview` sub-skill via the Skill tool, passing this scenario and the detection map from step 1.

If `plan-preview` returns `proceed: false`, exit cleanly. Do not invoke any step.

### 4. Execute steps in order

Track completed steps in a running list so halt-and-report can surface them on failure:

```json
[]
```

For each step in the plan:

#### 4a. If `action === "skip"` (kit missing)

Announce the skip and note which downstream capability is lost:

| Missing kit | Downstream impact |
|---|---|
| `speckit` missing | Findings will not be filed as issues. The swarm step also cannot run (it needs filed issues to dispatch). |
| `swarmkit` missing | Filed issues remain open; no parallel resolution. |

Append a synthetic entry to `completed_steps` with `outputSummary: "skipped — <kit> not installed"` so the state is visible in any later halt report. Continue to the next step.

#### 4b. If `action === "run"` (safe step — polishkit:critique)

Invoke `polishkit:critique` via the Skill tool. On success, capture the critique report path or summary in `outputSummary` and append to `completed_steps`. On failure, invoke `halt-and-report` (see step 5) and stop.

#### 4c. If `action === "pause"` (risky step)

Re-confirm with the user before running this specific step. Prefer `AskUserQuestion`; fall back to a plain prompt:

```
About to run <stepName> (<owningKit>). This will <side-effect>. Proceed? (yes / no)
```

Side-effect descriptions per step:

| Step | Side-effect phrase |
|---|---|
| `catalog findings as issues` | "file GitHub issues for each critique finding" |
| `swarm issues in parallel`   | "spawn parallel worktree agents and open stacked PRs" |

If the user declines, append `outputSummary: "declined by user"` to `completed_steps` and continue to the next step. If the user confirms, invoke the owning skill:

- `catalog findings as issues` → `speckit:catalog` via the Skill tool, passing the critique report from the previous step
- `swarm issues in parallel` → `swarmkit:swarm` via the Skill tool, passing the issue numbers filed by the catalog step

On success, capture the result summary in `outputSummary` and append to `completed_steps`. On failure, invoke halt-and-report (step 5).

### 5. On any step failure — halt and report

Invoke the `halt-and-report` sub-skill via the Skill tool with this payload:

```json
{
  "scenario": "polish-cycle",
  "completed_steps": "<the running list from step 4>",
  "failed_step": {
    "stepName": "<name of the step that threw>",
    "owningKit": "<owningKit from the plan>",
    "error": "<raw error string>",
    "skillState": "<any structured output the failing skill returned, or {}>"
  }
}
```

After invoking halt-and-report, stop. Take no further action.

### 6. Completion summary

After all steps finish (run, skipped, or declined), print:

```
/polish-cycle complete.

  ✓ <stepName>  —  <outputSummary>     (completed steps)
  ⊘ <stepName>  —  skipped             (missing-kit steps)
  ○ <stepName>  —  declined by user    (user-declined steps)
```

If any steps were skipped due to missing kits, append:

```
Note: the following steps could not run because their kit was not found:
  ⊘ <stepName>  —  <owningKit> not found in environment
```

## Notes

- `polishkit` is the only hard requirement. Missing it makes the scenario unavailable, not degraded.
- Per-step confirmation (`pause`) is independent of the overall plan gate from `plan-preview`. Both must pass before a risky step runs.
- The `speckit:catalog` step receives the critique report as context; `swarmkit:swarm` receives the issue numbers from catalog. If catalog was skipped or declined, swarm has no input — treat it as if its kit were missing (skip it and note the upstream dependency).
- This skill never modifies repository state directly — all mutations are delegated to the invoked skills.
