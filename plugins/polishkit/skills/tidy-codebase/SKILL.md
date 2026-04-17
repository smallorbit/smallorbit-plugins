---
name: tidy-codebase
description: Codebase hygiene sweep — find and clean up stale files, outdated documentation, build artifacts, and accumulated cruft. Use when the user asks to tidy, clean up, sweep, or find cruft in a codebase.
triggers:
  - "tidy up"
  - "tidy the codebase"
  - "clean up the codebase"
  - "find cruft"
  - "codebase hygiene"
---

Codebase hygiene sweep: find and clean up stale files, outdated documentation, build artifacts, and accumulated cruft.

## Scope

Focus area (if provided): $ARGUMENTS
If no focus area is provided, perform a full sweep across all categories below.

## Process

### 1. Scan for cruft

Run these checks in parallel and compile findings:

**Stale documentation**
- WIP/tracking files that reference completed work (check git log for last-modified dates)
- PRDs and task files for features that shipped months ago
- Handoff or planning docs for work that's long finished
- Docs with broken internal links or references to deleted files

**Build artifacts & dead directories**
- Empty directories, leftover build output not in .gitignore
- Generated files committed by accident (.DS_Store, logs, temp files)
- Unused config files (e.g., for tools no longer in use)

**Documentation gaps**
- README or user-facing docs that don't reflect current features
- Keyboard shortcuts, env vars, or CLI commands that were added but not documented
- Stale screenshots or media that no longer match the app

**Duplicate content**
- Root-level files that duplicate content already in docs/ (e.g., CONTRIBUTING.md vs docs/contributing.md)
- Repeated information across CLAUDE.md, AGENTS.md, README.md, etc.

**Git hygiene**
- Local branches whose upstream has been merged (`git branch --merged main` and cross-reference with remote)
- Stale worktrees (`git worktree list` — flag any where the branch no longer exists or has been merged)
- Orphaned remote-tracking branches (`git remote prune origin --dry-run`)

### 2. Present findings and confirm each action

Organize findings into a clear summary grouped by category:
- **Remove** — files/directories to delete (with reason)
- **Update** — docs that need content changes (with what's wrong)
- **Keep** — anything you considered but decided to keep (with why)

After presenting the summary, use `AskUserQuestion` to confirm each proposed action individually. Group into at most 4 questions per call (the tool limit); batch closely related items (e.g. two merged remote branches) into a single question. Each question should:
- State the specific action (delete X, update Y, remove reference to Z)
- Provide a short reason in the description of each option
- Default the first option to the recommended action (label it `(Recommended)`)

Wait for all answers before proceeding to step 3.

### 3. Execute cleanup

After approval:
1. If stale worktrees were identified in the scan, run `polishkit:tidy-codebase` cleanup, then proceed
2. Make all deletions and edits
3. Commit with message `chore: tidy codebase` and open a PR targeting develop
