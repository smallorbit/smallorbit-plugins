---
name: get-session-id
description: Resolve the current Claude Code session ID from ~/.claude/projects/. Sub-skill used by other sessionkit skills.
allowed-tools: Bash
---

# Get Session ID

Resolves the current Claude Code session ID from the working directory's session metadata.

## Sub-skill

This is an internal sub-skill. Called by other sessionkit skills — not typically invoked directly.

## Logic

```bash
PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g')
ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl
```

## How It Works

1. Encode the current working directory (`$PWD`) by replacing all `/` with `-`
2. List all session files in `~/.claude/projects/<encoded-path>/` sorted by modification time (newest first)
3. Take the most recent file
4. Extract the filename without the `.jsonl` extension — this is the session UUID

## Output

The session ID as a UUID string (e.g., `0400b9cb-7c5f-4721-8cb2-4bc61c38620d`).

## Path Encoding Scheme

The path encoding replaces `/` with `-`. For example:
- `/Users/roman/src/my-project` → `Users-roman-src-my-project`
- `/workspace/project` → `workspace-project`
