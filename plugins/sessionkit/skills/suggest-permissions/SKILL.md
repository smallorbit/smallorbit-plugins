---
name: suggest-permissions
description: Analyze recent Claude Code session history to identify permissions you repeatedly approved, then suggest additions to .claude/settings.json to reduce future prompts.
triggers:
  - "/suggest-permissions"
  - "suggest permissions"
  - "what permissions should I add"
  - "reduce permission prompts"
  - "I keep approving the same things"
  - "analyze my approvals"
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
---

# Suggest Permissions

Scan recent Claude Code session history to surface permission patterns — Bash commands, file edits, and MCP tools you approved repeatedly — and propose additions to `.claude/settings.json` so you stop seeing the same prompts.

## Process

### 1. Locate session history

Use `/get-session-id` to resolve the current session, then scan recent session files:

```bash
PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g')
ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -5
```

Read the most recent session files and extract tool approval events.

### 2. Identify patterns

Scan for repeatedly approved operations across three categories:

**Bash commands** — look for patterns like:
- Package managers: `npm`, `yarn`, `pnpm`, `bun`, `pip`, `cargo`
- VCS: `git`
- Language runtimes: `node`, `python`, `ruby`, `go`
- Project-specific scripts or directories

**File edits** — look for patterns like:
- Consistently approved source directories: `src/`, `lib/`, `app/`
- File types: `*.ts`, `*.py`, `*.md`
- Config files: `*.json`, `*.yaml`

**MCP tools** — any MCP tool approved more than once in recent sessions.

A pattern qualifies if it appears 2+ times across recent sessions, or if you can see the user approved it without hesitation.

### 3. Propose additions

Format suggestions as a `permissions.allow` block for `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Bash(git:*)",
      "Edit(src/**)",
      "Edit(*.ts)"
    ]
  }
}
```

For each suggestion, provide a one-line rationale so the user can make an informed decision. Group by category (Bash / Edit / MCP).

### 4. Apply on approval

If the user approves some or all suggestions:

1. Read the existing `.claude/settings.json` (or `settings.local.json` if they prefer local-only)
2. Merge the approved entries into the `permissions.allow` array
3. Write the file back

If no `.claude/settings.json` exists, create it with the minimal structure needed.

### 5. Confirm

Report what was added and where. Suggest running `/suggest-permissions` again after a few sessions to catch new patterns.

## Constraints

- Never write to settings files without explicit user approval
- Suggest project-level `.claude/settings.json` by default; offer `settings.local.json` as an alternative for personal preferences that shouldn't be committed
- Do not suggest wildcard patterns broader than what the evidence supports (e.g., don't suggest `Bash(*:*)` just because many commands were approved)
- If session history is unavailable or empty, say so and stop
