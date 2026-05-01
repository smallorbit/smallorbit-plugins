# Swarmkit — Stacked Agent/PR Methodology

## Overview

Swarmkit resolves a batch of GitHub issues by spawning one agent per issue, each working in its own isolated git worktree. When issues are independent, the agents run fully in parallel and open pull requests that target the base branch directly. When issues depend on one another, the dependent agent branches from its dependency's branch tip instead of from the base, and opens its pull request against that dependency's branch — forming a stack. A separate merge step then retargets every non-root PR to the base branch up front, then merges the stack bottom-up — root first, then each former child in turn — with a uniform squash, landing each PR's own closing references natively as it merges.

This shape exists because large features rarely factor cleanly into one pull request. The traditional alternatives are both painful: either the author opens one huge PR that is slow to review and risky to merge, or they open a sequence of PRs manually and spend significant effort keeping branches rebased against one another. Stacked pull requests — pioneered in tools like Gerrit and Phabricator and popularized on GitHub by Graphite and Aviator — solve this by treating each change as a small, independently reviewable unit that is explicitly stacked on its predecessor. Swarmkit takes the same idea and combines it with agent parallelism: independent work happens concurrently, dependent work is stacked, and both categories share a single merge strategy.

The four ideas that make this work together are worktree isolation (so agents cannot step on each other), the stacked branch strategy (so dependent work can start before its predecessor merges), bottom-up merging with up-front retargeting (so GitHub does not auto-close dependent PRs and so each PR lands with the same diff that was reviewed), and loop mode with failure handling (so a long queue of issues can be cleared without manual babysitting).

## Quick Start

If you just want to run a swarm and merge the result, this is the full shape of the workflow:

```
/next-issue          # see what is ready to work on
/swarm 12 15 18      # spawn parallel agents for specific issues
/merge-stack         # merge all open swarm PRs bottom-up (use /merge-pr for a single PR)
/clean-worktrees     # remove the worktree directories and orphaned branches
```

`/swarm` accepts three argument shapes. With specific issue numbers it runs in one-shot mode: each issue gets an agent, each agent opens a pull request, and the command exits. With no arguments it runs in loop mode: it fetches every open issue, ranks them, picks a safe batch to parallelize, swarms it, and repeats until the board is clear. With a single label argument it runs in loop mode filtered to that label.

Each agent does the same thing: creates a branch named `worktree-agent-<issue>`, makes the changes described in the issue, commits in conventional-commit format, pushes, and opens a pull request whose body includes `Closes #<issue>`. The agent then stops. Nothing is merged automatically — swarm agents open PRs and leave them open for your review.

When you are ready to merge the stack, run `/merge-stack`. It identifies every open pull request whose head branch starts with `worktree-agent-`, works out the stack graph from the head/base relationships, retargets every non-root PR in each chain to the base branch, and then merges each chain bottom-up — root PR first, then its former children, up to the leaf — with a uniform `gh pr merge <N> --squash --delete-branch`. Each PR closes its own `Closes #N` references natively as it merges.

## How It Works

### Worktree Isolation

Every swarm agent runs in a separate git worktree under `.claude/worktrees/agent-<issue>`. A git worktree is a second checkout of the same repository attached to a different branch, sharing the same object database but with its own working directory and index. This means agents can edit files, stage changes, and commit simultaneously without any file-level conflicts and without needing multiple clones of the repository. The official `git worktree` documentation covers the mechanics in full.

Isolation is enforced at the start of every agent prompt. Before doing any work, each agent runs a safety check that aborts if its current working directory does not contain the substring `worktrees`. This is a last line of defence against a misconfigured spawn accidentally editing files in the main checkout and pushing commits to the wrong branch.

Agents are instructed to use only relative paths. Absolute paths that include the main repository root would bypass the worktree and land edits in the primary checkout, defeating isolation. The swarm skill makes this explicit in every agent prompt.

Cleanup is an explicit step. `/clean-worktrees` removes every worktree directory under `.claude/worktrees/` and every local branch matching `worktree-agent-*`. The branch naming convention is not decorative — it is the mechanism that makes cleanup safe and automatic.

### Stacked Branch Strategy

When `/swarm` receives a batch of issues, it parses each issue body for `Depends on #N` and `Blocked by #N` references and builds a directed acyclic graph. Issues with no edges within the batch are independent and spawn in parallel. Issues with edges are dependent and spawn in topological order, each branching from its dependency's branch tip rather than from the base branch.

Concretely, an independent agent starts like this:

```bash
git checkout develop && git pull origin develop
git checkout -b worktree-agent-<issue>
```

A dependent agent starts like this instead:

```bash
git fetch origin worktree-agent-<dependency-issue>
git checkout -b worktree-agent-<issue> origin/worktree-agent-<dependency-issue>
```

The dependent agent's pull request then targets the dependency's branch rather than the base:

```bash
gh pr create --base worktree-agent-<dependency-issue> --head worktree-agent-<issue> ...
```

This is the stack. Each pull request in a chain has a head branch and a base branch that is the head branch of the pull request below it. The lowest PR in a chain targets `develop` (or whatever base was configured). GitHub understands this relationship natively and, critically, automatically retargets the dependent PR to the base branch when the dependency merges.

The reason this works as a concurrency primitive is that the dependent agent already has access to everything the upstream agent produced — the upstream output is in the working tree from the moment the dependent branch is created. The dependent agent never needs to wait for the upstream pull request to merge. That is also why swarmkit forbids merging a dependency PR mid-swarm "to unblock" a downstream agent: the downstream agent is already unblocked by virtue of branching from the upstream tip, and an early merge would bypass your review gate for no gain.

### Bottom-Up Merge with Up-Front Retargeting

The naive way to merge a stack bottom-up fails badly on GitHub: when the root PR merges and its branch is deleted, the PR immediately above it loses its base branch, and GitHub interprets the missing base as abandonment and auto-closes the dependent PR. You end up fighting the platform to re-open and re-target PRs that were perfectly healthy a minute earlier.

`/merge-stack` sidesteps this with an up-front retarget. Before any merge runs, every non-root PR in a multi-PR chain is retargeted to the base branch with `gh pr edit <N> --base $BASE`. Once a child's base is the base branch, deleting its predecessor's branch no longer looks like abandonment — the auto-close cascade never fires. This is the direction used by Graphite, git-spice, Sapling, and Phabricator, and it means the diff a reviewer approves is the diff that lands: no successive rebases into the root, no CI re-runs on a growing stack, no ref-juggling to preserve closing metadata.

With retargeting in place, every PR merges uniformly with `gh pr merge <N> --squash --delete-branch`. There is no per-role strategy matrix and no intermediate-branch sweep — `--delete-branch` handles cleanup inline. Each PR's own body closes its own `Closes #N` references natively as it merges. Chains merge from the root upward to the leaf; independent PRs (whose base is already `develop` and that have nothing stacked on them) may merge in any order.

If a merge halts partway up a chain (for example, because of a conflict), the remaining PRs above the halt point are marked blocked and reported at the end. Each PR above the halt still targets the base branch after the retarget, so the user can resolve the conflict and re-run `/merge-stack` without re-threading the stack.

### Loop Mode and Failure Handling

Loop mode is what turns swarmkit from "resolve these three issues" into "clear the board." When `/swarm` is invoked with no issue numbers (and optionally a single label filter), it repeats the following cycle until there are no open issues left.

Each cycle fetches the current open issues, ranks them, and selects a batch that can safely parallelize: no two issues touching the same files, no unresolved dependencies within the batch. The batch is presented in the next-issue table format, agents spawn, pull requests open. A checkpoint summary prints — how many PRs opened, which issues failed, which issues are now blocked because a dependency failed, how many issues remain — and the loop proceeds immediately to the next cycle.

Failure is handled explicitly rather than by retrying. If an issue fails during a cycle, every remaining issue in this and future cycles is checked for file overlap with the failed issue or explicit references to it. Anything that overlaps is marked blocked and skipped, with the block reported at each checkpoint. The loop continues with everything that is not blocked.

A small set of failures are treated as unrecoverable and halt the loop immediately: an agent that crashed without producing a PR (there is nothing to review, so there is nothing to proceed from) and the base branch being deleted or corrupted externally (the premise of the loop is gone). Everything else is recoverable and surfaces in the checkpoint report.

Loop mode sets `claude.prBase` as a local git config at the start and unsets it in teardown. While it is set, every pull request created in the repository targets that base, which is what keeps independent PRs merging into the intended base branch even when the command line that created them did not specify `--base`. The teardown unset is critical — leaving the config set leaks the scoped base into unrelated PR-creation commands in the same repository.

## End-to-End Walkthrough

Consider a small epic with three issues.

- **#101** — introduces a `ReportSerializer` class. Independent.
- **#102** — adds a CSV exporter that uses `ReportSerializer`. Depends on #101.
- **#103** — adds a CLI flag that calls the CSV exporter. Depends on #102.

You invoke `/swarm 101 102 103`. Swarmkit fetches the three issue bodies, parses `Depends on` and `Blocked by` references, and produces a topological order: #101 is independent, #102 depends on #101, #103 depends on #102. The swarm plan is presented before any agent runs, showing three agents, their branches (`worktree-agent-101`, `worktree-agent-102`, `worktree-agent-103`), the files affected, and the proposed model per agent.

Agent 101 spawns first. It branches from `origin/develop`, writes the `ReportSerializer` class, commits with `feat(reports): add ReportSerializer`, pushes `worktree-agent-101`, and opens PR #201 with base `develop` and head `worktree-agent-101`.

Agent 102 waits for #201 to exist, then spawns. It does not wait for #201 to merge. It fetches `origin/worktree-agent-101` and branches from that tip, so the new `ReportSerializer` class is already in its working tree. It adds the CSV exporter on top, commits, pushes `worktree-agent-102`, and opens PR #202 with base `worktree-agent-101` and head `worktree-agent-102`.

Agent 103 waits for #202 to exist, then spawns. It fetches `origin/worktree-agent-102` and branches from that tip, so both the serializer and the exporter are present. It wires up the CLI flag, commits, pushes `worktree-agent-103`, and opens PR #203 with base `worktree-agent-102` and head `worktree-agent-103`.

At this point three PRs are open: #201 (→ `develop`), #202 (→ `worktree-agent-101`), #203 (→ `worktree-agent-102`). You review each one. None of them has merged yet.

You run `/merge-stack`. It discovers the three PRs by scanning for open PRs with `worktree-agent-` head branches, builds the stack graph from the head/base fields, retargets every non-root PR to `develop`, and prints a merge plan:

```
Chain 1:  develop ← PR #201 ← PR #202 ← PR #203

  Retargeted 2 non-root PRs to develop: #202, #203
  Step 1. Merge PR #201 into develop (squash, delete branch)
  Step 2. Merge PR #202 into develop (squash, delete branch)
  Step 3. Merge PR #203 into develop (squash, delete branch)
```

Step 1 squash-merges #201 into `develop` and deletes `worktree-agent-101`. Because #202 was already retargeted to `develop`, GitHub does not auto-close it — #202's base is still `develop`. Step 2 squash-merges #202 into `develop` and deletes `worktree-agent-102`; step 3 does the same for #203. Each PR carries its own `Closes #10N` reference, so each issue closes natively on merge. Finally `/clean-worktrees` removes the three worktree directories and the three local `worktree-agent-*` branches.

If anything had gone wrong on the way up — a merge conflict on #202, for example — the merge would have stopped there and reported the chain as halted at #202 with #203 as blocked upstream. The retarget happened before the first merge, so #203 still targets `develop`; the user can resolve the conflict on #202 and re-run `/merge-stack` without re-threading the stack.

## Layered Review with `/swarm-plus`

`/swarm` produces PRs and stops — the review and any follow-up work are manual. `/swarm-plus` layers an automatic review/fix pass on top of the same swarm machinery: same arg grammar, same isolation, same final state of open PRs awaiting human merge.

The shape is a single deterministic pass per PR. As each swarm agent's notification lands, `/swarm-plus` dispatches the swarmkit-vendored `swarm-reviewer` agent for that PR in the background — no waiting for other swarm agents. The reviewer compares the PR diff against the originating issue's acceptance criteria and returns its findings inline, in a fixed five-section structure (Verdict / Blockers / Concerns / Nits / Coverage gaps). The orchestrator parses the result and applies a skip-on-clean rule: if the verdict is `Approve` with no blockers, no concerns, and no `[recommended]` coverage gaps, no further action is taken on that PR. If the reviewer surfaces blockers, concerns, or recommended coverage gaps, a worker is spawned to address them. The worker branches off the existing PR head — never off the base — so its commits stack directly onto the PR rather than diverging.

The single-pass rule is intentional. There is no reviewer-after-worker re-review; if you want a second opinion on the worker's commits, run `/review <pr>` manually. Manufactured churn ("just look at it again") is worse than no-op for a layer that is supposed to compress your review burden, not replicate it. Nits and `[optional]` coverage gaps never trigger a worker — the bar to dispatch is meaningful enough to materially change the PR.

The reviewer is vendored into swarmkit (`plugins/swarmkit/agents/swarm-reviewer.md`) rather than imported from another plugin, so `/swarm-plus` carries no cross-marketplace dependency. Worker scope is constrained: blockers and concerns are in scope, recommended coverage gaps are in scope, optional coverage gaps and nits are out of scope along with any unrelated cleanups. The worker may comment once on the PR summarizing what it addressed and what it deferred; the reviewer never posts comments.

The skill exposes three flags beyond the inherited `/swarm` set: `--review-only` for triage runs that review without dispatching workers, `--reviewer-model <tier>`, and `--worker-model <tier>`. Both model overrides default to `sonnet`.

`/swarm-plus` is the right layer when you want every swarm PR to land with at least one independent pass against its acceptance criteria, and when the acceptance criteria in the originating issue are crisp enough for a reviewer to evaluate against. It is not a replacement for human review on the final merge — every PR still ends in the same place: open, awaiting your merge.

## Further Reading

- How do stacked diffs work — https://graphite.com/guides/how-do-stacked-diffs-work
- Stacked PRs: Code Changes as Narrative — https://www.aviator.co/blog/stacked-prs-code-changes-as-narrative/
- Rethinking code reviews with stacked PRs — https://www.aviator.co/blog/rethinking-code-reviews-with-stacked-prs/
- How Gerrit Works — https://gerrit-review.googlesource.com/Documentation/intro-how-gerrit-works.html
- git-worktree Documentation — https://git-scm.com/docs/git-worktree
