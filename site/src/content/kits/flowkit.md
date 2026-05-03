---
name: flowkit
role: Git workflow automation — branching, PRs, releases, and hotfixes
accentColor: "var(--flowkit)"
oneLiner: Ship features faster with opinionated Git flow built for Claude Code.
commands:
  - /flowkit:create-branch
  - /flowkit:pr
  - /flowkit:merge-pr
  - /flowkit:cut
  - /flowkit:release
  - /flowkit:hotfix
  - /flowkit:sync
  - /flowkit:stage
  - /flowkit:pipeline-status
  - /flowkit:preview-epic
  - /flowkit:cut-epic
summary: >
  flowkit wraps the full develop → release → main lifecycle into a set of
  Claude Code skills. It handles branch creation, PR opening with structured
  bodies, squash-merging, staging cuts, hotfixes, and release tagging — so
  every merge follows the same convention without manual steps.
---

flowkit is the backbone of the smallorbit release pipeline.
