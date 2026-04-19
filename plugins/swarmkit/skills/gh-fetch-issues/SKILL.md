---
name: gh-fetch-issues
description: Fetch open GitHub issues and filter out on-hold labeled issues. Sub-skill used by next-issue, swarm, and catalog.
---

# gh-fetch-issues

Tier 4 sub-skill (internal component, not user-facing). Provides the canonical fetch-and-filter pattern for open GitHub issues.

## Command

```bash
gh issue list --limit 50 --state open --json number,title,body,labels \
  --search '-label:"status:in-progress"'
```

## Filter Rule

Filter out any issue with the `on-hold` label — do not surface, rank, or recommend them. They are not ready to be worked.

Also filter out any issue with the `status:in-progress` label — these are actively being worked on by a swarm agent and should not be re-picked until the agent completes.
