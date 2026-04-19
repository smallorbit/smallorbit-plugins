---
name: halt-and-report
description: Surface a structured failure report when any step inside a metakit scenario fails mid-flow, then present the user with a rule-based next-command suggestion.
---

# Halt and Report

Called by a scenario skill the moment any step returns an error. Captures what ran, what failed, and the current repo state, then emits a report that makes recovery obvious. All recovery decisions stay with the user — this skill never retries or cleans up automatically.

## Inputs

The invoking scenario passes a single JSON payload:

```json
{
  "scenario": "<scenario name>",
  "completed_steps": [
    { "stepName": "string", "outputSummary": "string" }
  ],
  "failed_step": {
    "stepName": "string",
    "owningKit": "string",
    "error": "string",
    "skillState": {}
  }
}
```

| Field | Description |
|---|---|
| `scenario` | Human-readable name of the scenario that was running |
| `completed_steps` | Ordered list of steps that finished successfully before the failure |
| `completed_steps[].stepName` | Name of the completed step |
| `completed_steps[].outputSummary` | One-line summary of what the step produced |
| `failed_step.stepName` | Name of the step that threw |
| `failed_step.owningKit` | The plugin kit that owns the failing step (e.g. `swarmkit`, `speckit`) |
| `failed_step.error` | Raw error string or exception message |
| `failed_step.skillState` | Any structured state the failing skill returned before throwing (may be `{}`) |

## Process

1. **Record the input payload** — hold `scenario`, `completed_steps`, and `failed_step` in memory for the report.

2. **Capture repo state** — run the following three commands and store their output:
   - `git rev-parse --abbrev-ref HEAD` → active branch
   - `git status --porcelain` → dirty-file summary (empty string if clean)
   - `git worktree list` → list of in-flight worktrees

3. **Determine the suggested next command** using these rules in order:

   | Condition | Suggestion |
   |---|---|
   | `failed_step.error` contains `merge conflict` (case-insensitive) | `abort and clean up` |
   | `failed_step.error` contains `CONFLICT` | `abort and clean up` |
   | `git status --porcelain` shows unmerged paths (`UU`, `AA`, `DD` prefixes) | `abort and clean up` |
   | `failed_step.owningKit` is `swarmkit` and active branch is a `worktree-agent-*` branch | `abort and clean up` |
   | `failed_step.skillState` contains a `retryable: true` field | `retry <failed_step.stepName>` |
   | `failed_step.error` matches a transient pattern (`timeout`, `rate limit`, `ECONNRESET`, `503`) | `retry <failed_step.stepName>` |
   | None of the above match | `retry <failed_step.stepName>` (default — let the user decide) |

   "Skip to next step" is offered as an alternative choice in the report but is never the primary recommendation; it suits optional/non-blocking steps and the user is better placed to judge.

4. **Format the halt report** per the Output shape section below.

5. **Print the report** to the terminal. Do not write it to a file. Do not take any further action.

## Output shape

```
═══════════════════════════════════════════════
 HALT: <scenario>
═══════════════════════════════════════════════

Completed steps
───────────────
  ✓ <stepName>  —  <outputSummary>
  ✓ <stepName>  —  <outputSummary>
  (empty if no steps completed)

Failed step
───────────
  ✗ <stepName>  (<owningKit>)
  Error: <error>
  <skill state rendered as indented key: value pairs, omitted if empty>

Repo state
──────────
  Branch:    <active branch>
  Dirty:     <git status --porcelain output, or "clean">
  Worktrees: <git worktree list output>

Suggested next command
──────────────────────
  → <suggested command>

Other options
─────────────
  • retry <failed_step.stepName>
  • abort and clean up
  • skip to next step

All recovery decisions are yours. This skill has taken no automated action.
═══════════════════════════════════════════════
```

### Suggested-next-command values

| Value | When to expect it |
|---|---|
| `retry <stepName>` | Transient errors or unknown conditions |
| `abort and clean up` | Merge conflicts, unmerged index entries, swarm worktree collisions |
| `skip to next step` | Never the primary suggestion; always listed as an option |

## Notes

- **No auto-retry.** This skill never re-invokes a failed step or skill.
- **No auto-clean.** This skill never runs `git worktree remove`, `git checkout`, or any destructive command.
- **No file writes.** The report is printed to stdout only; no log files or state files are created.
- **No side effects.** Calling this skill is always safe — it is read-only with respect to the repo.
- The `skillState` field may contain partial work (e.g. a half-written spec draft). The skill surfaces it in the report so the user can recover it manually if needed.
- If `git worktree list` returns only the main worktree, print it anyway — absence of agent worktrees is itself useful signal.
