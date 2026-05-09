---
name: flowkit
role: Git workflow automation — branching, PRs, and releases
oneLiner: Ship features faster with opinionated Git flow built for Claude Code.
commands:
  - /flowkit:create-branch
  - /flowkit:pr
  - /flowkit:merge-pr
  - /flowkit:cut
  - /flowkit:release
  - /flowkit:sync
  - /flowkit:ship-epic
  - /flowkit:restack
  - /flowkit:pipeline-status
  - /flowkit:cut-epic
summary: >
  flowkit wraps the full develop → release → main lifecycle into a set of
  Claude Code skills. It handles branch creation, PR opening with structured
  bodies, squash-merging, rebase-merge release tagging, and epic promotion —
  so every merge follows the same convention without manual steps.
---

flowkit is the backbone of the smallorbit release pipeline.
