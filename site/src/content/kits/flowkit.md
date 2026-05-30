---
name: flowkit
role: Git workflow automation — branching, PRs, and releases
oneLiner: Ship features faster with opinionated Git flow built for Claude Code.
commands:
  - /flowkit:commit
  - /flowkit:pr
  - /flowkit:open-pr
  - /flowkit:merge-pr
  - /flowkit:ship
  - /flowkit:sync
  - /flowkit:pipeline-status
  - /flowkit:migrate-v4
summary: >
  flowkit wraps the full feature-branch → squash-merge → release lifecycle into
  a set of Claude Code skills. It handles committing dirty workspaces, opening
  PRs with structured bodies against main, squash-merging, semver tagging, and
  GitHub release creation — so every merge and release follows the same
  convention without manual steps.
---

flowkit is the backbone of the smallorbit release pipeline.
