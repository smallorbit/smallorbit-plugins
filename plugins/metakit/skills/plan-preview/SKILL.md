---
name: plan-preview
description: Render an execution plan table for a metakit scenario, prompt for confirmation, and return a structured plan with run/skip/pause status per step.
---

# Plan Preview

## Inputs

### Scenario definition

An ordered list of steps describing what the scenario intends to do:

```json
[
  { "stepName": "string", "owningKit": "string", "riskLevel": "safe" | "risky" }
]
```

- `stepName` — human-readable label for this step
- `owningKit` — the kit that owns execution of this step (matched against the detection result)
- `riskLevel` — `safe` for steps that may run automatically; `risky` for steps that require user confirmation before proceeding

### Detection result

The map returned by the `detect-kits` sub-skill:

```json
{
  "<kitName>": { "version": "string", "scope": "string", "skills": ["string"] }
}
```

## Process

1. **Derive status for each step** by applying these rules in order:
   - If `owningKit` is not a key in the detection result → `skip (kit missing)`
   - Else if `riskLevel` is `risky` → `pause (risky)`
   - Else → `run`

2. **Compose a short rationale** (`Notes` column) for each row:
   - `run` — `"<owningKit> detected at <version>"`
   - `skip (kit missing)` — `"<owningKit> not found in environment"`
   - `pause (risky)` — `"requires confirmation before proceeding"`

3. **Render the table** to the user:

   ```
   | Step | Kit | Status | Notes |
   |------|-----|--------|-------|
   | <stepName> | <owningKit> | run / skip (kit missing) / pause (risky) | <rationale> |
   ```

4. **Prompt for confirmation**. Use `AskUserQuestion` where available:

   ```
   Proceed with this execution plan?
   ```

   If `AskUserQuestion` is not available, print:

   ```
   Proceed with this execution plan? (yes / no)
   ```

   and parse the next user message for an affirmative (`yes`, `y`) or negative (`no`, `n`) response.

## Output shape

```json
{
  "steps": [
    {
      "stepName": "string",
      "owningKit": "string",
      "action": "run" | "skip" | "pause",
      "notes": "string"
    }
  ],
  "proceed": true | false
}
```

- `action` mirrors the derived status: `"run"`, `"skip"`, or `"pause"`
- `proceed` is `true` if the user confirmed, `false` if they declined

## Notes

- **Caller contract**: callers must not begin execution until `proceed` is `true`. Steps with `action: "pause"` must be re-confirmed individually by the caller before running — plan-preview only gates the plan as a whole.
- **Confirmation fallback**: if neither `AskUserQuestion` nor user input is available (non-interactive context), set `proceed` to `false` and surface an error asking the caller to re-invoke interactively.
- This skill is read-only — it never modifies environment state. All execution decisions are deferred to the calling scenario.
