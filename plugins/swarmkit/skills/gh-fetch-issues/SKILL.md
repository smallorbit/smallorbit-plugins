---
name: gh-fetch-issues
description: Fetch open GitHub issues and filter out on-hold labeled issues. Sub-skill used by pick-issue, swarm, and catalog.
---

# gh-fetch-issues

Tier 4 sub-skill (internal component, not user-facing). Provides the canonical fetch-and-filter pattern for open GitHub issues.

## Command

```bash
gh issue list --limit 50 --state open --json number,title,body,labels
```

## Filter Rule

Filter out any issue with the `on-hold` label — do not surface, rank, or recommend them. They are not ready to be worked.
