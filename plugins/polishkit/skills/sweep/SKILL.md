---
name: sweep
description: Sweep accumulated cruft from a codebase — both dead code (unused exports, imports, variables, unreachable branches) and stale artifacts (outdated docs, build leftovers, duplicate content, merged branches). Use when the user asks to sweep, tidy, clean up, find cruft, remove dead code, or eliminate unused exports/imports/variables.
triggers:
  - "sweep"
  - "sweep the codebase"
  - "tidy up"
  - "clean up the codebase"
  - "find cruft"
  - "codebase hygiene"
  - "find dead code"
  - "remove dead code"
  - "unused exports"
  - "unused imports"
  - "dead variables"
  - "unreachable code"
---

# /sweep — Codebase Hygiene & Dead Code Sweep

Sweep accumulated cruft from a codebase in a single pass: both dead code at the language level (unused exports, imports, variables, unreachable branches) and stale artifacts at the file level (outdated docs, build leftovers, duplicate content, git debris).

## Scope

Focus area (if provided): $ARGUMENTS
If no focus area is provided, perform a full sweep across both phases below.

A scope can be:
- A path or glob (`src/components/`, `**/*.test.ts`) — restricts both phases to that subtree.
- A category hint (`dead-code-only`, `cruft-only`, `git-only`) — runs just the matching phase.
- Empty — run everything.

## Process

The skill runs in two phases. Each phase scans, reports, and confirms before modifying anything. Phases are independent — if scope restricts to one, skip the other.

### Phase 1 — Dead Code

#### 1.1 Detect language and available tools

Identify the primary language(s) in the repo and check for available static analysis tools:

**TypeScript / JavaScript**
```bash
ls tsconfig.json 2>/dev/null && echo "TypeScript project"
ls .eslintrc* eslint.config* 2>/dev/null
```

**Python**
```bash
which pyflakes vulture ruff 2>/dev/null
```

**Go**
```bash
which staticcheck 2>/dev/null
```

#### 1.2 Scan for dead code

Run all applicable checks in parallel:

**Unused exports (TypeScript)**
```bash
npx ts-prune 2>/dev/null || \
  grep -rn "^export " --include="*.ts" --include="*.tsx" | \
  grep -v "node_modules" | head -100
```

**Unused imports**
- TypeScript: `tsc --noEmit` often surfaces these; or ESLint `no-unused-vars`
- Python: `pyflakes .` or `ruff check --select F401 .`
- Go: compiler enforces this — no unused imports compile

**Dead variables / unreachable branches**
- TypeScript: `tsc --noEmit` for `noUnusedLocals`, `noUnusedParameters`
- Python: `vulture .` for dead code detection
- Go: `staticcheck ./...`

**Commented-out code blocks**
```bash
grep -rn "^[[:space:]]*//" --include="*.ts" --include="*.tsx" | \
  awk -F: '{print $1 ":" $2}' | uniq -c | awk '$1 >= 3 {print}'
```

Skip findings in:
- `node_modules/`, `dist/`, `build/`, `.next/`
- Generated files (`*.generated.ts`, `*.d.ts`)
- Test files (dead code in tests can be intentional fixtures)

#### 1.3 Compile findings

Group by category:

| Category | Count | Severity |
|----------|-------|----------|
| Unused exports | N | Medium |
| Unused imports | N | Low |
| Dead variables | N | Low |
| Unreachable branches | N | High |
| Commented-out code | N | Low |

For each finding, show file:line, the snippet (1–3 lines), and why it's considered dead.

### Phase 2 — Cruft & Hygiene

Run these checks in parallel and compile findings:

**Stale documentation**
- WIP/tracking files that reference completed work (check git log for last-modified dates)
- PRDs and task files for features that shipped months ago
- Handoff or planning docs for work that's long finished
- Docs with broken internal links or references to deleted files

**Build artifacts & dead directories**
- Empty directories, leftover build output not in `.gitignore`
- Generated files committed by accident (`.DS_Store`, logs, temp files)
- Unused config files (e.g., for tools no longer in use)

**Documentation gaps**
- README or user-facing docs that don't reflect current features
- Keyboard shortcuts, env vars, or CLI commands that were added but not documented
- Stale screenshots or media that no longer match the app

**Duplicate content**
- Root-level files that duplicate content already in `docs/` (e.g., `CONTRIBUTING.md` vs `docs/contributing.md`)
- Repeated information across `CLAUDE.md`, `AGENTS.md`, `README.md`

**Git hygiene**
- Local branches whose upstream has been merged (`git branch --merged main` cross-referenced with remote)
- Stale worktrees (`git worktree list` — flag any where the branch no longer exists or has been merged)
- Orphaned remote-tracking branches (`git remote prune origin --dry-run`)

### 3. Present findings and confirm each action

Organize findings into a single combined summary across both phases:

- **Remove** — files/directories/code to delete (with reason)
- **Update** — docs that need content changes (with what's wrong)
- **Keep** — anything you considered but decided to keep (with why)

Use `AskUserQuestion` to confirm each proposed action, batched in groups of at most 4 questions per call. Group closely related items into a single question (e.g. two merged remote branches together). Each question should:

- State the specific action (delete X, update Y, remove reference to Z)
- Provide a short reason in the description of each option
- Default the first option to the recommended action (label it `(Recommended)`)

Wait for all answers before proceeding to step 4.

### 4. Execute cleanup

After approval:

1. Apply all confirmed removals and edits.
2. For dead-code removals, verify the file still parses — run `tsc --noEmit` or the language equivalent if available.
3. After all changes, re-run the project's verify command (typecheck/test) if one is exposed.
4. Commit with `chore: sweep codebase` and open a PR targeting the project's base branch (auto-detect `develop` then fall back to `main`).
