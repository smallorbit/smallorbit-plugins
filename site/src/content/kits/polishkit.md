---
name: polishkit
role: Polish it — appraise craft, sweep cruft, polish cross-cutting issues
oneLiner: Codebase quality toolkit — score craft across 5 dimensions, sweep dead code and stale artifacts, polish cross-cutting fixes in one PR.
commands:
  - /polishkit:appraise
  - /polishkit:sweep
  - /polishkit:polish
summary: >
  polishkit is the quality gate between swarm and release. /appraise scores a
  scope across elegance, architecture, and craft. /sweep clears unused exports,
  imports, dead branches, and stale build artifacts in a single confirmed pass.
  /polish fixes cross-cutting reuse / quality / efficiency issues across a
  themed scope in an isolated worktree, gated on your project's verify commands.
---

polishkit sits between execution and release — sharpen what the swarm just built.
