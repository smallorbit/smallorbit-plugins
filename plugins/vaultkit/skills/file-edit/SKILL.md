---
name: file-edit
description: Edit an Obsidian vault file while preserving its filesystem birth time. Use whenever editing an existing vault file via the Edit tool — macOS resets birth time on file rename (which Edit uses internally).
---

# Obsidian File Edit

Edits an Obsidian vault file while preserving its filesystem birth time. The Edit tool on macOS uses a temp-file-rename strategy that resets the file's birth time — this skill wraps that operation to restore it.

## When to use

Invoke this sub-skill any time you need to edit an existing file in an Obsidian vault. For **new files** created with the Write tool, use `SetFile -d "$(date '+%m/%d/%Y %H:%M:%S')" "$PATH"` directly — there is no prior birth time to preserve.

## Steps

### 1. Capture birth time (before editing)

```bash
BIRTH=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "$VAULT_PATH/path/to/file.md")
```

### 2. Edit the file

Use the Edit tool to make the change.

### 3. Restore birth time

```bash
SetFile -d "$BIRTH" "$VAULT_PATH/path/to/file.md"
```

### 4. Verify

```bash
stat -f "Birth: %SB | %N" "$VAULT_PATH/path/to/file.md"
```

## Notes

- `$VAULT_PATH` is the vault root obtained via `obsidian vault=<VAULT> vault`
- Always capture birth time **before** any edit — not after
- This does not apply to `obsidian append`/`obsidian prepend` CLI commands — those preserve metadata natively
