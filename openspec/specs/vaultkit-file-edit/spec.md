# Obsidian File Edit

## Purpose
Obsidian File Edit modifies an existing file in an Obsidian vault while preserving the file's filesystem birth time. It exists because Claude's `Edit` and `Write` tools use a temp-file-rename strategy on macOS that resets birth time, which corrupts the `created` field Obsidian derives from birth time for dataview queries, sort orders, and plugin behaviors.

## Requirements

### Requirement: Applicability to existing vault files
The skill SHALL be used whenever an existing file in an Obsidian vault is modified. It SHALL NOT be used for creating new files, where there is no prior birth time to preserve.

#### Scenario: Editing an existing vault file
- **WHEN** an existing file in an Obsidian vault needs to be modified
- **THEN** the skill is invoked to apply the change in place so the existing birth time is preserved

#### Scenario: Creating a new vault file
- **WHEN** a new vault file is being created rather than an existing one edited
- **THEN** the `Write` tool is used directly, followed by `SetFile -d "$(date '+%m/%d/%Y %H:%M:%S')" "$PATH"`, because there is no prior birth time to preserve

#### Scenario: Append or prepend via the Obsidian CLI
- **WHEN** content is added through the `obsidian append` or `obsidian prepend` CLI commands
- **THEN** the skill does not apply, because those commands preserve metadata natively

### Requirement: Birth-time preservation via in-place inode write
The skill SHALL modify the existing file's inode so its filesystem birth time is unchanged after the edit. It SHALL NOT use the `Edit` or `Write` tools in the primary flow, because their temp-file-rename strategy resets birth time on macOS.

#### Scenario: In-place write preserves birth time
- **WHEN** the skill writes new content through an in-place mechanism such as shell `>` redirect, `cat > file <<EOF`, `python3 open(p, "w")`, or `node fs.writeFileSync`
- **THEN** the existing inode is modified and the file's birth time is preserved

#### Scenario: Rename-based tools are avoided in the primary flow
- **WHEN** the primary in-place write flow is used
- **THEN** the `Edit` and `Write` tools are not used, because they reset birth time

### Requirement: Happy-path in-place write sequence
The skill SHALL read the current file contents, compute the new content in memory, write the full new content in place via a shell mechanism that modifies the existing inode, and then verify the birth time is unchanged.

#### Scenario: Reading current contents first
- **WHEN** an edit begins
- **THEN** the current file contents are loaded with the `Read` tool before changes are computed

#### Scenario: Writing the full new content in place
- **WHEN** the new content has been computed in memory
- **THEN** the full new file content is piped to the target path via a shell redirect heredoc (`cat > "$PATH" <<'VAULTKIT_EOF' ... VAULTKIT_EOF`)

#### Scenario: Heredoc-marker-safe or binary-safe write
- **WHEN** the content may contain the heredoc marker, or a binary-safe write is required
- **THEN** the content is written via `python3 -c 'import sys; open(sys.argv[1], "w").write(sys.stdin.read())' "$PATH"` instead

### Requirement: Verification of preserved birth time
After writing, the skill SHALL verify that the file's birth time matches its value before the edit.

#### Scenario: Verifying birth time after write
- **WHEN** the in-place write has completed
- **THEN** `stat -f "Birth: %SB | %N" "$PATH"` is run and the reported birth time matches what it was before the edit

### Requirement: Large-file fallback using SetFile
The skill SHALL provide a fallback for cases where rewriting the whole file is measurably wasteful, such as a multi-megabyte note where only a handful of lines change. In that fallback the skill SHALL capture the birth time, apply a targeted change with the `Edit` tool, and restore the captured birth time with `SetFile`. The skill SHALL prefer the in-place write for typical files and reach for the fallback only when whole-file rewriting is genuinely expensive.

#### Scenario: Large file with a small targeted change
- **WHEN** the file is large enough that reading and re-writing the whole thing is measurably expensive and only a few lines change
- **THEN** the birth time is captured with `stat`, the targeted change is applied with the `Edit` tool, and the captured birth time is restored with `SetFile -d "$BIRTH" "$PATH"`

#### Scenario: Typical file size
- **WHEN** the file is of typical size
- **THEN** the in-place write happy path is used in preference to the fallback

### Requirement: Vault path resolution
The skill SHALL operate on the file relative to the vault root, which is obtained via the `obsidian vault=<VAULT> vault` command and referenced as `$VAULT_PATH`.

#### Scenario: Resolving the vault root
- **WHEN** the target file path is constructed
- **THEN** the vault root `$VAULT_PATH` obtained via `obsidian vault=<VAULT> vault` is used as the base for the file path
