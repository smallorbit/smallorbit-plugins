---
name: pick-issue
description: List open GitHub issues and recommend the best one(s) to work on next, based on priority, implementation specificity, and architectural impact.
triggers:
  - "what should I work on next"
  - "recommend an issue"
  - "list open issues"
  - "what's next"
  - "pick an issue"
  - "which issue should I tackle"
---

# Pick Issue Skill

Fetches open GitHub issues, analyzes them, and recommends the best next task.

## Process

### 1. Fetch all open issues

Follow the `gh-fetch-issues` sub-skill to fetch and filter issues.

This excludes both `on-hold` issues (not ready to work) and `status:in-progress` issues (already in-flight with an active swarm agent).

### 2. Identify top candidates

Follow the `issue-rank` sub-skill to rank issues by priority, specificity, and impact.

For the top 3–5 candidates, fetch the full body:

```bash
gh issue view <number>
```

### 3. Present a ranked summary

Output a table:

```
| # | Title | Priority | Why consider it |
|---|-------|----------|-----------------|
| N | ...   | high     | Fully specced, unblocks #X |
| N | ...   | medium   | Atomic, low risk |
| N | ...   | low      | Quick win, cleanup |
```

### 4. Give a recommendation

State clearly:
- **Primary recommendation** — the single best issue to start now, with 2–3 sentence rationale
- **Runner-up** — alternative if the primary seems too large or risky right now, with tradeoff explained

### 5. Wait for the user to choose

Do not start implementation. The user will confirm which issue to work on, then invoke `/swarm`, `/push`, or start directly.

## Notes

- If the issue list is empty, say so and suggest running `/catalog` to generate new issues from codebase findings
- When two issues touch the same files, flag the conflict so the user can sequence them
