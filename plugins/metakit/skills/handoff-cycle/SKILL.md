---
name: handoff-cycle
description: Wrap up a session cleanly in one command — archives the conversation export, jots session progress to the vault, and writes a handoff document. Auto-infers vault project, session summary, and handoff destination.
triggers:
  - "/handoff-cycle"
  - "wrap up the session"
  - "close out the session"
  - "end of session cycle"
---

# Handoff Cycle

Single-command session close-out. Runs three steps in sequence — archive export, vault jot, and handoff document — auto-inferring all inputs where possible and pausing for confirmation on each write.

## Steps

### 1. Detect installed kits

Call the `detect-kits` sub-skill. Hold the detection map for use in steps 2 and 3.

### 2. Infer inputs

Before rendering the plan, resolve the three inputs the scenario needs. Do this silently — do not print intermediate results.

**Vault project**

Check conversation context for an active vault project (e.g. the most recently mentioned project name, or a prior `/load-project` call). If context is clear, use it. If not, check whether vaultkit is installed and call its active-project detection:

```
Read ~/.claude/settings.json and recent tool outputs for the last referenced vaultkit project.
```

If no project can be inferred and vaultkit is installed, ask:

```
Which vault project should archive-export and jot target?
```

Skip this question if vaultkit is absent from the detection map (the vault steps will be marked skip anyway).

**Session summary**

Synthesise a single sentence from the last 5–10 conversation turns that captures the session's goal and outcome. This becomes the jot entry and the handoff Goal context. Example: `"Implemented /handoff-cycle scenario command for metakit."` Do not ask the user — derive from context.

**Handoff destination**

Use sessionkit's default path: `<working-dir>/.sessionkit/HANDOFF.md`. Derive `<working-dir>` from CWD. Do not ask.

### 3. Preview the plan

Call the `plan-preview` sub-skill with the following scenario definition and the detection map from step 1:

```json
[
  {
    "stepName": "vaultkit:archive-export — file the session export to the vault",
    "owningKit": "vaultkit",
    "riskLevel": "risky"
  },
  {
    "stepName": "vaultkit:jot — record session progress in the vault project",
    "owningKit": "vaultkit",
    "riskLevel": "risky"
  },
  {
    "stepName": "sessionkit:handoff — write the handoff document",
    "owningKit": "sessionkit",
    "riskLevel": "risky"
  }
]
```

The preview will render a table, then ask "Proceed with this execution plan?". Wait for the user's response.

If the user declines (`proceed: false`), stop here. Print:

```
Handoff cycle cancelled. No changes were made.
```

### 4. Execute steps

For each step where `action` is not `skip`, execute in order. All three steps in this scenario are `risky`, so they will always carry `action: "pause"` when the owning kit is present. Steps with `action: "skip"` are silently bypassed; they were already surfaced in the preview.

Track completed steps and failed steps for error reporting (see step 5).

#### Step 4a — vaultkit:archive-export

Show:

```
About to archive the session export to vault project "<vault-project>".
Confirm? (yes / no)
```

Wait for confirmation. If the user declines, skip this step (do not record it as a failure).

Invoke `vaultkit:archive-export`. Pass the inferred vault project as context. Record the result summary as a completed step.

#### Step 4b — vaultkit:jot

Show:

```
About to jot session progress to vault project "<vault-project>":
  "<session-summary>"
Confirm? (yes / no)
```

Wait for confirmation. If declined, skip.

Invoke `vaultkit:jot` with the inferred session summary as `$ARGUMENTS`. Record the result as a completed step.

#### Step 4c — sessionkit:handoff

Show:

```
About to write handoff document to <handoff-destination>.
Confirm? (yes / no)
```

Wait for confirmation. If declined, skip.

Invoke `sessionkit:handoff`. Pass the inferred session summary as `$ARGUMENTS` to seed the Goal section. Record the result as a completed step.

### 5. Handle mid-flow failure

If any step throws an error (and the user did not decline it), immediately call the `halt-and-report` sub-skill with this payload shape:

```json
{
  "scenario": "handoff-cycle",
  "completed_steps": [
    { "stepName": "<name>", "outputSummary": "<one-line summary of what the step produced>" }
  ],
  "failed_step": {
    "stepName": "<name of the step that threw>",
    "owningKit": "<vaultkit or sessionkit>",
    "error": "<raw error message>",
    "skillState": {}
  }
}
```

Populate `completed_steps` with all steps that succeeded before the failure. Do not continue to subsequent steps after calling `halt-and-report`.

### 6. Confirm completion

If all non-skipped, non-declined steps complete successfully, print a summary:

```
Handoff cycle complete.

  ✓ archive-export  —  filed to <vault-project>/Conversations/<filename>
  ✓ jot             —  progress recorded in <vault-project>
  ✓ handoff         —  written to <handoff-destination>
```

Omit rows for steps that were skipped (kit missing) or declined by the user.

## Graceful degradation

When one or both kits are absent from the detection map, the `plan-preview` table will show the affected steps as `skip (kit missing)`. The cycle continues with whatever steps remain.

Concrete cases:

| vaultkit | sessionkit | Behaviour |
|----------|------------|-----------|
| present  | present    | All three steps previewed and run |
| absent   | present    | Archive-export and jot shown as skip; handoff runs |
| present  | absent     | Archive-export and jot run; handoff shown as skip |
| absent   | absent     | All steps shown as skip; cycle exits after preview |

When all steps would be skipped, stop after the plan-preview and print:

```
No installed kits support any handoff-cycle steps. Install vaultkit and/or sessionkit to use this command.
```

## Notes

- This skill never writes files directly — all writes are delegated to the owning kit skills.
- Each risky step requires individual confirmation even after the user approves the overall plan in the preview; that is the contract specified in `plan-preview`'s caller contract.
- If the session summary is genuinely uninferable (e.g. the conversation contains only tool noise with no user turns), ask the user for a one-line summary before proceeding.
