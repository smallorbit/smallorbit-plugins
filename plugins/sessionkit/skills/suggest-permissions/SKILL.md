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

## Process

### 1. Locate session history

Claude Code stores per-session `.jsonl` files under `~/.claude/projects/<encoded-cwd>/`, where `<encoded-cwd>` is `$PWD` with every `/` replaced by `-`. Locate the directory, list JSONL files sorted by modification time (most recent first), and read the five most recent. Extract tool approval events from each.

### 2. Identify patterns

Scan for repeatedly approved operations across three categories:

- **Bash commands** — package managers, VCS, language runtimes, project-specific scripts.
- **File edits** — source directories, file globs, config files.
- **MCP tools** — any MCP tool approved more than once.

A pattern qualifies if it appears 2+ times across recent sessions, or if the user approved it without hesitation.

### 3. Propose additions

For each suggestion, provide a one-line rationale so the user can make an informed decision. Group by category (Bash / Edit / MCP).

After presenting the suggestions, call the `AskUserQuestion` tool to request approval — a single question such as "Apply these permissions to settings.json?" with options like `Apply all`, `Select individually`, and `Cancel`. Do not proceed to step 4 until the user has answered via `AskUserQuestion`.

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
- After presenting suggestions, always request approval via the `AskUserQuestion` tool — not prose. A silent wait with no tool call is a defect.
- Suggest project-level `.claude/settings.json` by default; offer `settings.local.json` as an alternative for personal preferences that shouldn't be committed
- Do not suggest wildcard patterns broader than what the evidence supports (e.g., don't suggest `Bash(*:*)` just because many commands were approved)
- If session history is unavailable or empty, say so and stop
