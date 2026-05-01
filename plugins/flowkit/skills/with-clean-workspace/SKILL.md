---
name: with-clean-workspace
description: Auto-stash uncommitted changes around a command that triggers an implicit `git pull` (e.g. `gh pr merge --squash --delete-branch`). Sub-skill used by merge-pr and release.
---

# with-clean-workspace

Wrap a command whose side effects include an implicit `git pull` (most notably `gh pr merge --squash --delete-branch` / `--merge --delete-branch`) so a dirty workspace cannot break the post-merge pull with `cannot pull with rebase: You have unstaged changes`.

The guard auto-stashes uncommitted changes (tracked + untracked) before the wrapped command and pops the stash after. If the pop conflicts, it leaves the stash on the stack and surfaces that to the user — never auto-resolves.

## Process

### 1. Detect dirty workspace before the wrapped command

```bash
DIRTY=false
if [ -n "$(git status --porcelain)" ]; then
  DIRTY=true
  git stash push -u -m "flowkit-auto-stash" >/dev/null
fi
```

### 2. Run the wrapped command

Whatever the caller needs to invoke (`gh pr merge ...`, etc.).

### 3. Restore the stash if one was pushed

```bash
if [ "$DIRTY" = "true" ]; then
  if ! git stash pop; then
    echo "WARNING: stash pop conflicted. Your changes are preserved on the stash stack." >&2
    echo "Run \`git stash list\` to see the saved entry (message: flowkit-auto-stash) and \`git stash pop\` after resolving." >&2
  fi
fi
```

## Constraints

- Never auto-resolve a stash-pop conflict — leave the stash on the stack and tell the user.
- Always use `-u` so untracked files (e.g. new hook scripts) are stashed too.
- Use the literal message `flowkit-auto-stash` so the user can identify the entry in `git stash list`.
