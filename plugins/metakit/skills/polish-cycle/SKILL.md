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
  { "stepName": "critique codebase",       "owningKit": "polishkit", "riskLevel": "safe" },
  { "stepName": "catalog findings as issues", "owningKit": "speckit",   "riskLevel": "risky" },
  { "stepName": "swarm issues in parallel",   "owningKit": "swarmkit",  "riskLevel": "risky" }
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
  "completed_steps": [ { "stepName": "...", "outputSummary": "..." } ],
  "failed_step": {
    "stepName": "<current step's stepName>",
    "owningKit": "<current step's owningKit>",
    "error": "<error string from the failing skill>",
    "skillState": { }
  }
}
```

Stop after halt-and-report prints. Do not attempt further steps, retries, or cleanup — recovery is the user's decision.

### 6. On clean completion

When every step has either run, skipped, or been declined without error, print a one-line summary:

```
/polish-cycle complete — <N> ran, <N> skipped, <N> declined.
```

List any skipped steps' downstream-impact notes so the user knows what was not done.

## Notes

- This skill is a thin orchestrator; all heavy lifting (critique, catalog, swarm) lives in the owning kits.
- A risky step that is *skipped* because its kit is missing does not trigger a confirmation pause — only risky steps whose kit is present do.
- `plan-preview` gates the plan as a whole; individual risky steps must still be re-confirmed per the caller contract (see `plan-preview` notes).
- Never chain around a failure. Halt-and-report is the only failure path.
