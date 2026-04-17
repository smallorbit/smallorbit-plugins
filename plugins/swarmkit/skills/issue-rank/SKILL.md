---
name: issue-rank
description: Canonical ranking table for prioritizing GitHub issues by priority labels, specificity, architectural impact, and testability. Sub-skill used by pick-issue and swarm.
---

# Issue Rank Sub-Skill

## Ranking Table

| Signal | Weight |
|--------|--------|
| `priority:high` label | Highest |
| `priority:medium` label | High |
| Subtasks already defined in body | High (lower friction) |
| Architectural impact (unblocks other work) | High |
| `priority:low` / `cleanup` labels | Low |
| No label | Medium (read body to judge) |

## Assessment Criteria

For deeper evaluation of top candidates:

- **Specificity** — are exact files, line numbers, or interfaces called out? More specific = lower risk.
- **Scope** — is this a focused atomic change or a sprawling refactor?
- **Dependencies** — does this block or unblock other open issues?
- **Testability** — can the outcome be verified mechanically (tsc, tests, grep)?

## Notes

- If `priority:high` issues exist, always surface them — don't bury them behind architectural preferences
- A well-specced `priority:medium` issue often beats a vague `priority:high` one for autonomous agent work
