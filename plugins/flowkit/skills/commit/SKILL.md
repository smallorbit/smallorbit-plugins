---
name: commit
description: Stage and commit workspace changes using conventional commits. Splits changes into logical commits when multiple concerns are present.
triggers:
  - "/commit"
  - "stage and commit"
  - "commit changes"
  - "commit all"
  - "commit these changes"
allowed-tools: Bash
---

# Commit

Stage and commit all current workspace changes. The conventional-commit type, scope, and subject are **derived from the staged diff** in the current turn — there is no operator interview for type/scope/subject inputs. Splits changes into logical commits when multiple unrelated concerns are present. The operator may edit the proposed message before commit, but is not prompted to supply the type, scope, or subject.

## Input

`$ARGUMENTS` — optional freeform context or description to inform the commit message (e.g. "this fixes the login timeout issue"). If omitted, infer everything from the diff. Even when `$ARGUMENTS` is provided, the conventional-commit type/scope/subject are still derived from the diff; `$ARGUMENTS` only adds context to the body and the subject phrasing.

## Message Derivation

Read the staged diff and derive the message components:

- **Type** — inferred from the change shape. New files / new behavior → `feat`. Bug-fix patterns → `fix`. Doc-only edits → `docs`. Code reorganization without behavior change → `refactor`. Test additions → `test`. Formatting only → `style`. Dependency/maintenance changes → `chore`.
- **Scope** — inferred from the changed paths. If the diff touches files under a single conventional scope (e.g. `plugins/flowkit/skills/x/...`), the scope is set accordingly (e.g. `flowkit:x` or `flowkit`). If the diff spans multiple plausible scopes, the dominant scope (most lines changed, or the most semantically central) is selected; cross-cutting concerns are noted in the body rather than the subject.
- **Subject** — a short imperative description of *what changed*, under 72 characters total including the `type(scope): ` prefix.

If the workspace diff contains multiple unrelated concerns, split into one commit per logical concern, each with its own derived conventional-format message.

## Conventional Commit Format

Every commit message must follow this format:

```
type(scope): description
```

### Type Enum

- `feat` — new feature
- `fix` — bug fix
- `chore` — maintenance, dependency updates, no functional change
- `refactor` — code reorganization without behavior change
- `docs` — documentation changes
- `test` — test additions or changes
- `style` — formatting, no functional change

### Subject Line

Keep the subject line (first line) under 72 characters.

### Body

Add a body when the "why" isn't obvious from the diff:
- Blank line after subject
- Explain the motivation or reason for the change
- Wrap at 72 characters

## Process

### 1. Inspect current state

Run these in parallel to understand what's changed:

```bash
git status
git diff --cached
git diff
```

If `git status` is clean, report "Nothing to commit" and stop. Never amend a previous commit — always create new ones.

### 2. Identify logical groupings

Examine the changed files and their diffs. Group files by concern — each group should represent a single logical change (e.g. a new feature, a bug fix, a dependency bump). If all changes belong to one concern, there is one commit. If multiple concerns are present, plan one commit per concern.

If `$ARGUMENTS` is provided, use it to inform the commit message subject and body.

### 3. For each group: stage, write message, commit

For each logical group, in order:

**a. Stage the relevant files:**

```bash
git add <file1> <file2> ...
```

To stage all remaining changes in one pass (only when grouping is complete):

```bash
git add -A
```

**b. Write the commit message** following the conventional commit format above.

**c. Commit using HEREDOC syntax:**

```bash
git commit -m "$(cat <<'EOF'
type(scope): short description under 72 chars

Optional body explaining the why, wrapped at 72 chars.
EOF
)"
```

Omit the body when the subject line is self-explanatory.

### 4. Confirm

After all commits are made, run:

```bash
git log --oneline -5
```

Report what was committed.
