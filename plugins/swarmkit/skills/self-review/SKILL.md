---
name: self-review
description: Run up to 3 passes of /simplify on changed files, committing and pushing between passes. Sub-skill used by ship and swarm agents.
---

# Self-Review

Iterative quality pass on changed files. Runs `/simplify` in a loop, committing improvements between passes.

## Process

Track a pass count starting at 0 (max 3).

1. Run `/simplify` on the changed files
2. Check for changes: `git diff`
   - **Changes found AND pass count < 3** — commit with `/commit`, push with `git push`, increment pass count, go back to step 1
   - **No changes found OR pass count >= 3** — pass loop converged; return to caller and continue with the caller's remaining workflow steps

## Notes

- This is a Tier 4 sub-skill (internal component)
- The first clean pass (no changes) exits immediately — most code needs 0–1 passes
- Callers are responsible for establishing the diff context (e.g., `gh pr diff`) before invoking
