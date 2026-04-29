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

Claude Code stores per-session `.jsonl` files under `~/.claude/projects/<encoded-cwd>/`, where `<encoded-cwd>` is `$PWD` with every `/` replaced by `-`. The most recent file's basename (minus `.jsonl`) is the active session UUID.

```bash
PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g')
ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl
```

Output: a UUID string (e.g. `0400b9cb-7c5f-4721-8cb2-4bc61c38620d`).
