---
name: conventional-commit-message
description: Canonical commit message format rules — conventional commits, type enum, 72-char subject, body guidelines. Sub-skill used by commit and swarm.
---

## Format

Commit messages must follow the conventional commits format:

```
type(scope): description
```

## Type Enum

Use one of these types:
- `feat` — new feature
- `fix` — bug fix
- `chore` — maintenance, dependency updates, no functional change
- `refactor` — code reorganization without behavior change
- `docs` — documentation changes
- `test` — test additions or changes
- `style` — formatting, no functional change

## Subject Line

Keep the subject line (first line) under 72 characters. This preserves readability in `git log --oneline` output.

## Body

Add a body if the "why" isn't obvious from the diff:
- Blank line after subject
- Explain the motivation or reason for the change
- Wrap at 72 characters for readability

## Critical Constraints

- Keep commit messages clear and focused on a single logical change
