---
name: archive-export
description: Archive the latest /export output into the active Obsidian project's Conversations folder. Use after the user runs /export session from the workspace root.
triggers:
  - "archive the export"
  - "save the conversation"
  - "file the export"
  - "archive this conversation"
---

# Archive Export

## Overview

Picks up the latest conversation export and files it into the active Obsidian project's `Conversations/` folder.

## Convention

The user always runs `/export session` from the current working directory. This produces a consistent file:

```
./session.txt
```

This skill creates two copies in the project's `Conversations/` folder: a `.txt` file (plain text, well-formatted when viewed natively) and a `.md` file (Obsidian-renderable, searchable) that embeds the `.txt` as an attachment and includes the session ID for resuming the conversation.

## Steps

### 1. Confirm the file exists

```bash
ls -lh ./session.txt
```

If missing, remind the user to run `/export session` from this directory first.

### 2. Identify the active project

Use conversation context. If unclear, run:
```bash
obsidian vault=Personal files folder="Projects"
```
and ask the user which project to file it under.

### 3. Get the session ID

Claude Code stores per-session `.jsonl` files under `~/.claude/projects/<encoded-cwd>/`, where `<encoded-cwd>` is `$PWD` with every `/` replaced by `-`. The most recent file's basename (minus `.jsonl`) is the active session UUID:

```bash
PROJECT_PATH=$(echo "$PWD" | sed 's|/|-|g')
SESSION_ID=$(ls -t ~/.claude/projects/${PROJECT_PATH}/*.jsonl 2>/dev/null | head -1 | xargs basename -s .jsonl)
```

### 4. Ensure the Conversations folder exists

```bash
mkdir -p "$VAULT/Projects/ProjectName/Conversations"
```

Where `VAULT` is the path to your Personal vault.

### 5. Choose a filename

Base name format: `YYYY-MM-DD-HHMM-<slug>` (no extension yet)

This is the canonical filename format for conversation archives.

- Use today's date and current time (hours + minutes)
- Derive the slug from the session topic (2–4 words, hyphenated)
- Example: `2026-04-03-2314-backtest-snapshot-playbook-fix`

```bash
BASENAME=$(date '+%Y-%m-%d-%H%M')-your-slug-here
```

This base name is used for both files:
- `YYYY-MM-DD-HHMM-slug.txt` — plain text copy
- `YYYY-MM-DD-HHMM-slug.md` — Obsidian markdown copy

### 6. Copy the .txt file and stamp birth time

```bash
cp ./session.txt "$VAULT/Projects/ProjectName/Conversations/$BASENAME.txt"
```

Follow the `vaultkit:file-edit` sub-skill's new-file guidance to stamp the birth time on the copied `.txt`.

### 7. Create the .md file with session ID, attachment link + full content

The `.md` file has three parts:

1. A session ID line for resuming the conversation
2. An Obsidian attachment embed
3. The full conversation text in a `plaintext` fenced code block

Use the Bash tool to build and write the file in one step:

```bash
{
  echo "session-id: $SESSION_ID"
  echo "resume: claude --resume $SESSION_ID"
  echo ''
  echo "![[${BASENAME}.txt]]"
  echo ''
  echo '```plaintext'
  cat ./session.txt
  echo '```'
} > "$VAULT/Projects/ProjectName/Conversations/$BASENAME.md"
```

Then stamp its birth time per the `vaultkit:file-edit` sub-skill's new-file guidance.

### 8. Clean up the source file

```bash
rm ./session.txt
```

### 9. Confirm

Report both destination paths and the session ID to the user.

## Notes
- The `.txt` file is the source of truth for content; the `.md` file embeds it as an attachment and also inlines the full text in a `plaintext` block for Obsidian search indexing
- Both files should have the same base name — only the extension differs
- The session ID resolution logic is inlined above (step 3)
- To resume a session: `claude --resume SESSION_ID`
- If the user ran `/export` from the wrong directory, locate the file with:
  ```bash
  find . -name "session.txt" 2>/dev/null | head -5
  ```
