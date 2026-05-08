---
name: with-clean-workspace
description: Auto-stash uncommitted changes around a command that triggers an implicit `git pull` (e.g. `gh pr merge --squash --delete-branch`). Sub-skill used by merge-pr and release.
---

# with-clean-workspace

Wrap a command whose side effects include an implicit `git pull` (most notably `gh pr merge --squash --delete-branch` / `--merge --delete-branch`) so a dirty workspace cannot break the post-merge pull with `cannot pull with rebase: You have unstaged changes`.

The deterministic stash-guard behavior lives in [`scripts/with_clean_workspace.sh`](./scripts/with_clean_workspace.sh). Callers should invoke that script contract directly rather than re-implementing stash logic inline.

## Invocation

```bash
bash "$SKILL_DIR/scripts/with_clean_workspace.sh" -- <command> [args...]
```

`$SKILL_DIR` is the absolute runtime path to the *with-clean-workspace* skill (from the invocation header: `Base directory for this skill: ...`).

For cross-skill callers inside flowkit (for example `merge-pr` and `release`), derive the target skill path from the caller:

```bash
WITH_CLEAN_WORKSPACE_DIR="$(dirname "$SKILL_DIR")/with-clean-workspace"
bash "$WITH_CLEAN_WORKSPACE_DIR/scripts/with_clean_workspace.sh" -- <command> [args...]
```

## Contract

- Interface: `-- <command ...>`; missing `--` or command exits `2` with stderr usage text.
- Dirty workspace handling: stashes tracked + untracked changes (`git stash push -u -m "flowkit-auto-stash"`).
- Success path: restores stash (`git stash pop`).
- Pop conflict path: warns to stderr and leaves stash on stack.
- Failure path: keeps stash, warns to stderr, exits with wrapped command's non-zero exit code.
