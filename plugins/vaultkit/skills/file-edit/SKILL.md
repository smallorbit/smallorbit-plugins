---
name: file-edit
description: Edit an Obsidian vault file while preserving its filesystem birth time. Use whenever modifying an existing vault file — Claude's Edit/Write tools atomic-rename and reset birth time on macOS, which breaks Obsidian's `created` metadata.
---

# Obsidian File Edit

Edits an Obsidian vault file in place so its filesystem birth time is preserved. Claude's `Edit` and `Write` tools use a temp-file-rename strategy on macOS that resets birth time — this sub-skill writes through a process that modifies the existing inode instead.

Obsidian uses filesystem birth time for the `created` field in dataview queries, sort orders, and plugin behaviors. Every rename-based write corrupts that timeline.

## When to use

Invoke this sub-skill any time you need to edit an existing file in an Obsidian vault. For **new files**, use the `Write` tool then run `SetFile -d "$(date '+%m/%d/%Y %H:%M:%S')" "$PATH"` directly — there is no prior birth time to preserve.

This does not apply to `obsidian append`/`obsidian prepend` CLI commands — those preserve metadata natively.

## Happy path: in-place write

### 1. Read the file

Use the `Read` tool to load the current file contents.

### 2. Compute the new content in memory

Apply your edits to the content as a string. Do not call `Edit` or `Write` — they reset birth time.

### 3. Write in place

Pipe the full new content to the file via shell redirect. This modifies the existing inode and preserves birth time:

```bash
cat > "$VAULT_PATH/path/to/file.md" <<'VAULTKIT_EOF'
<full new file content here>
VAULTKIT_EOF
```

For content that may contain the heredoc marker, or for binary-safe writes, use python3:

```bash
python3 -c 'import sys; open(sys.argv[1], "w").write(sys.stdin.read())' \
  "$VAULT_PATH/path/to/file.md" <<'VAULTKIT_EOF'
<full new file content here>
VAULTKIT_EOF
```

### 4. Verify

```bash
stat -f "Birth: %SB | %N" "$VAULT_PATH/path/to/file.md"
```

Birth time should match what it was before the edit.

## Fallback: targeted diff-style edit on a very large file

If rewriting the whole file is genuinely wasteful (e.g. a multi-megabyte note where you are changing a handful of lines), the old three-step pattern still works:

```bash
BIRTH=$(stat -f "%SB" -t "%m/%d/%Y %H:%M:%S" "$VAULT_PATH/path/to/file.md")
# ...use the Edit tool to apply the targeted change...
SetFile -d "$BIRTH" "$VAULT_PATH/path/to/file.md"
```

Prefer the in-place write above for anything typical. Reach for this fallback only when the file is large enough that reading and re-writing the whole thing is measurably expensive.

## Notes

- `$VAULT_PATH` is the vault root obtained via `obsidian vault=<VAULT> vault`
- `Edit`, `Write`, and the `SetFile -d` dance are no longer part of the happy path — they are documented only as a fallback
- Shell `>` redirect, `cat > file <<EOF`, `python3 open(p, "w")`, and `node fs.writeFileSync` all write in place on macOS; `Edit` and `Write` do not
