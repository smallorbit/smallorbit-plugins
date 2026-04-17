---
name: dead-code
description: Scan the codebase for dead code — unused exports, unreachable branches, dead variables, and obsolete imports — and remove it after confirmation. Use when the user asks to find dead code, remove unused code, or clean up unused exports/imports/variables.
triggers:
  - "find dead code"
  - "remove dead code"
  - "unused exports"
  - "unused imports"
  - "dead variables"
  - "unreachable code"
  - "clean up unused"
---

# Dead Code Eliminator

Scan for dead code — unused exports, unreachable branches, dead variables, and obsolete imports — and remove it after confirmation.

## Scope

Focus area (if provided): $ARGUMENTS
If no focus area is provided, scan the entire codebase.

## Process

### 1. Detect language and available tools

Identify the primary language(s) in the repo and check for available static analysis tools:

**TypeScript / JavaScript**
```bash
# Check for TypeScript
ls tsconfig.json 2>/dev/null && echo "TypeScript project"
# Check for ESLint with unused-vars rule
ls .eslintrc* eslint.config* 2>/dev/null
```

**Python**
```bash
# Check for pyflakes, vulture, or ruff
which pyflakes vulture ruff 2>/dev/null
```

**Go**
```bash
# Check for staticcheck
which staticcheck 2>/dev/null
```

### 2. Scan for dead code

Run all applicable checks in parallel:

**Unused exports (TypeScript)**
```bash
# ts-prune or grep-based analysis
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

**Unreachable code patterns (language-agnostic grep)**
```bash
# Code after return/throw at same indentation level
grep -rn "return\b" --include="*.ts" --include="*.tsx" --include="*.js" .
```

**Commented-out code blocks**
```bash
# Large commented blocks (3+ consecutive comment lines)
grep -rn "^[[:space:]]*//" --include="*.ts" --include="*.tsx" | \
  awk -F: '{print $1 ":" $2}' | uniq -c | awk '$1 >= 3 {print}'
```

### 3. Compile and present findings

Group findings by category:

| Category | Count | Severity |
|----------|-------|----------|
| Unused exports | N | Medium |
| Unused imports | N | Low |
| Dead variables | N | Low |
| Unreachable branches | N | High |
| Commented-out code | N | Low |

For each finding, show:
- File path and line number
- The dead code snippet (1–3 lines)
- Why it's considered dead

Skip findings in:
- `node_modules/`, `dist/`, `build/`, `.next/`
- Generated files (`*.generated.ts`, `*.d.ts`)
- Test files (dead code in tests can be intentional fixtures)

### 4. Confirm before acting

Use `AskUserQuestion` to group findings into batches of at most 4 questions. For each batch:
- Describe what will be removed
- Show the file:line reference
- Default to the safe action (remove)
- Allow keeping if user prefers

Wait for all confirmations before proceeding.

### 5. Execute removals

For each confirmed removal:
1. Remove the dead code (delete lines, remove import, delete function/variable)
2. Verify the file still parses (run `tsc --noEmit` or language equivalent if available)
3. Report what was removed

After all removals:
```bash
# Verify nothing broke
tsc --noEmit 2>/dev/null || echo "No TypeScript to check"
```

Commit with: `chore: remove dead code` and open a PR targeting develop.
