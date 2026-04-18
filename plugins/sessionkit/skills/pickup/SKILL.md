---
name: pickup
description: Load a handoff document and orient the agent to continue a previous session's work. Use at the start of a new session after /handoff was run.
triggers:
  - "/pickup"
  - "pick up where we left off"
  - "load handoff"
  - "resume from handoff"
  - "continue previous session"
allowed-tools: Bash, Read
---

# Pickup

Companion to `/handoff`. At the start of a new session, invoke `/pickup` to restore context written by the previous agent into `.sessionkit/HANDOFF.md`, so work can continue seamlessly.

## Process

### 1. Discover handoff file

Check for `.sessionkit/HANDOFF.md` in the current working directory:

```bash
cat .sessionkit/HANDOFF.md 2>/dev/null
```

If the file does not exist, fail gracefully: report

> No handoff file found at `.sessionkit/HANDOFF.md`. Either `/handoff` was not run in the previous session, or you're in a different working directory.

Then stop — do not proceed with the remaining steps.

### 2. Read and parse

Read the full content of `.sessionkit/HANDOFF.md`. Parse the standard sections: **Project**, **Date**, **Branch**, **Goal**, **Progress**, **Git State**, **Remaining Work**, **Context**.

### 3. Present orientation summary

Output a structured summary to orient the agent. Surface essentials, not the document verbatim:

- **Goal** — restate clearly in one or two sentences
- **Progress** — summarize what was done and what decisions were made
- **Git State** — branch, staged/unstaged files, recent commits
- **Remaining Work** — list in priority order
- **Context** — surface any important gotchas or notes the next agent must know

### 4. Restore git state (if needed)

Compare the handoff's branch against the current branch:

```bash
git branch --show-current
```

If they differ, suggest:

```bash
git checkout <branch-from-handoff>
```

Only suggest this when there's a mismatch. Do not switch branches automatically.

### 5. Confirm readiness

End with:

> Context loaded. Ready to continue work on: `<Goal>`. What would you like to tackle first?

## Constraints

- Never modify or delete `.sessionkit/HANDOFF.md` — this skill is read-only with respect to the handoff file
- Do not assume the handoff file always exists — always check first and fail gracefully
- Keep the orientation summary concise — surface the essentials, not everything verbatim
- Do not automatically re-execute any commands referenced in the handoff — the goal is to orient, not to act
