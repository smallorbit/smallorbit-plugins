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

Whatever the caller needs to invoke (`gh pr merge ...`, etc.). Capture whether it succeeded:

```bash
if <wrapped-command>; then
  MERGE_OK=true
else
  MERGE_OK=false
fi
```

### 3. Restore the stash only if the wrapped command succeeded

The pop is conditional on the wrapped command exiting 0. If the command failed (e.g. merge conflict on GitHub, network error), the stash is left on the stack so the user can retry without losing their workspace state:

```bash
if [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "true" ]; then
  if ! git stash pop; then
    echo "WARNING: stash pop conflicted. Your changes are preserved on the stash stack." >&2
    echo "Run \`git stash list\` to see the saved entry (message: flowkit-auto-stash) and \`git stash pop\` after resolving." >&2
  fi
elif [ "$DIRTY" = "true" ] && [ "$MERGE_OK" = "false" ]; then
  echo "WARNING: merge failed — stash preserved. Run \`git stash pop\` after resolving the merge error." >&2
fi

[ "$MERGE_OK" = "false" ] && exit 1
```

