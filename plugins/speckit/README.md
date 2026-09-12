# Speckit

A Claude Code plugin for defining and capturing work. Interview a feature into existence, bulk-convert findings into issues, or quickly file a single issue — all from slash commands.

> **New to smallorbit-plugins?** Start with the [Getting Started walkthrough](../../README.md#getting-started) — it covers install, `/spec`, and `/swarm` end to end.

## Installation

Install from the `smallorbit-plugins` marketplace:

```
/plugin marketplace add smallorbit/smallorbit-plugins
/plugin install speckit@smallorbit-plugins
```

Or load directly for a single session:

```bash
claude --plugin-dir /path/to/speckit
```

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with repo access

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| **interview** | `/interview` | Conducts a structured interview to clarify requirements and produce a speckit-format plan (Goal, Background, Requirements, Out of Scope, Tasks); output feeds into `/spec` or `/catalog`. |
| **spec** | `/spec` | Interview-driven planning — gathers requirements, builds a structured plan, files it as a GitHub epic with linked child issues. |
| **catalog** | `/catalog` | Bulk-converts findings (from a code review, audit, or assessment) into prioritized, labeled GitHub issues. Also used internally by `/spec` to create child issues after plan approval. |
| **issue** | `/issue` | Quickly drafts and files a single GitHub issue from a description. Checks for duplicates and previews before creating. |

## Typical Workflows

### Spec out a feature

```
/spec add dark mode support       # Interview → plan → epic + issues
```

### Turn a code review into a backlog

```
/catalog                          # Pick up findings from earlier in the conversation
/catalog findings.md              # Or point at a file
/catalog --epic dark-mode         # Scope findings to an existing epic
```

### File a quick issue

```
/issue the login button is misaligned on mobile Safari
```

### Full planning session

```
/spec                             # Start with a blank slate — Claude will ask what to plan
/issue users can't reset password # File any loose issues that didn't need a full spec
```

## How Spec Works

`/spec` runs a structured interview using `AskUserQuestion` (1–4 questions per round), grounding each question in the actual codebase before asking. It continues until all ambiguities are resolved, then synthesizes a plan with goal, background, requirements, out-of-scope boundaries, and a task breakdown. The plan and its approval prompt are always emitted in the same turn — the plan never appears without an immediate `AskUserQuestion` call to approve, adjust, re-scope, or cancel.

Child issues are created via `/catalog`. An epic tracking issue is created last, after all child issue numbers are known. `/spec` then attaches every child to the epic as a native GitHub sub-issue and converts each task's `Depends On` value into a GitHub blocked-by relationship, so dependencies live in GitHub's issue graph rather than in issue-body text. Nothing is filed before you approve the plan.

### Simple-path shortcut

Before running the full interview, `/spec` classifies the request as **simple** or **full** based on a quick codebase scan. A request qualifies as simple when it is a single conceptual change AND touches a single file (or a few tightly co-located files in one skill/module directory).

Classification is silent when the heuristic is confident. `/spec` narrates the routing inline (e.g. "This looks like a single-file, single-concept change — running simple path") and proceeds. An upfront `AskUserQuestion` prompt fires only when the heuristic is genuinely ambiguous — for example, a single file containing multiple plausibly-independent concepts, or an input that under-specifies scope.

On both paths the plan-presentation turn always ends with an `AskUserQuestion` approval call — it's the mandatory plan-approval gate, and no issue is filed before it is answered. It isn't necessarily the only prompt you'll see: `/catalog` runs its own catalog-table confirmation before filing, and on the full path an already-existing `epic:<slug>` label prompts again before the epic tracking issue goes up. The prompt includes a re-scope option on both paths (`Run full interview instead` on a simple-path plan, `Condense to single issue` on a full-path plan), so the final approval is also the escape hatch.

On the simple path, `/spec` runs a single lightweight interview round (1–3 questions), drafts a one-task plan, and hands it to `/catalog` with **no `--epic` flag**. One standalone issue is filed — no epic tracking issue, no sub-issue wiring, no auto-appended documentation task (docs fold into the single issue's acceptance criteria). This keeps trivial changes from being inflated into multi-task epics.

### Consolidation signals

When `/spec` runs the full interview path, the interview skill applies a silent consolidation pass before presenting the plan, so related tasks don't appear as separate issues when they should ship together. Four merge signals:

1. **Same file + same logical change** — two tasks touching the same file and the same function or config block merge.
2. **Strict ordering, no standalone value** — a task that can't ship without its predecessor and adds no independent acceptance criteria merges back into that predecessor.
3. **Soft cap on epic size** — if the task count is still greater than 4 after signals 1 and 2, a second merge pass re-examines under looser interpretations of 1 and 2. The cap is a prompt to re-examine, not a hard limit — genuinely independent tasks are never forced together.
4. **Docs-only tail merge** — if the auto-appended documentation task is the only non-implementation task remaining and the impl task(s) cover the same surface, docs fold into impl.

### Team-readiness assessment

After the epic and child issues are filed, `/spec` (full path only) assesses
whether the work is well-suited for a parallel agent team. The signals it
scores against:

1. **Multiple independent modules** — work spans ≥2 modules / skills / packages.
2. **Clear interface boundaries** — at least one task can be expressed as a contract.
3. **Separable phases** — work splits into contract → implementation → integration waves.
4. **Non-trivial implementation surface** — ≥3 tasks, with multiple non-trivial edits.

If at least three signals hold, `/spec` re-decomposes the filed issues for
agent execution: it provisions `phase:1`, `phase:2`, `phase:3` labels (creating
them if missing, matching the catalog skill's label-provisioning pattern),
assigns each child issue to a phase, extracts interface contracts as their own
issue when bundled inside an implementation task, identifies the issue whose
branch should become the epic's feature-branch base, and posts a team dispatch
summary as a comment on the epic issue describing recommended spawn config
(builder count, model, feature branch, initial dispatch order).

If fewer than three signals hold, `/spec` prints
`Team decomposition skipped — <reason>` and proceeds to the final report. The
simple path always skips this step — single-issue plans are never team-suitable.

## How Catalog Works

`/catalog` accepts findings from three sources (checked in order): explicit input in `$ARGUMENTS`, findings from earlier in the conversation, or a file path. It parses them into discrete findings, provisions any labels the batch needs, shows a summary table for approval, then creates all issues in priority order (high first).

You can pass `--epic <slug>` to scope all created issues to an epic label:

```
/catalog --epic dark-mode
```

This attaches the `epic:dark-mode` label to every issue created in that run, without re-running the full `/spec` interview. If the label is missing it is created for you in the shared epic styling (purple `#5319e7`); if it already exists, `/catalog` warns once per invocation and waits for a `y/N` confirmation before reusing it across the batch. An epic title may follow the slug — it becomes the label description. Any `--epic` run ends with a fenced `spec-handoff` JSON block (the filed issue numbers and slug) intended for the `/spec` orchestrator; you'll see it on standalone runs too.

Pass `--auto` to skip the approval gate and proceed directly to issue creation. Use this for programmatic or scripted invocations (other skills, CI pipelines) where interactive confirmation is not needed. Omit it for interactive use when you want to review and adjust the catalog before anything is filed.

When the source is a multi-row blueprint table (e.g. a "Child issue list" grouped by phase), `/catalog` consolidates by default: rows in the same phase that share scope and have no inter-dependency fold into a single issue per phase, and a one-line per-phase summary prints before the catalog table so the consolidation decision is visible. Pass `--split` to disable this and file one issue per row.

## How Issue Works

`/issue` is the lightweight path. Give it a description, and it drafts a title, infers type and priority, checks for duplicates, and shows a preview before filing. Use it when you know exactly what to file and don't need an interview.

## Epic Labeling

When `/spec` produces a multi-task (epic) plan, it derives an `epic:<slug>` label and applies it to the epic tracking issue and every child issue, making the epic and all its work filterable in GitHub's issue list with a single label query. Simple-path, single-issue plans skip slug derivation entirely and get no epic label.

The slug is derived from the feature title or goal: lowercase the title, strip filler words (`the`, `a`, `an`, `enhance`, `add`, `update`, `to`, `for`, `of`, `in`), replace spaces and non-alphanumeric characters with hyphens (collapsing runs), then trim to 30 characters (not counting the `epic:` prefix).

| Input title | Derived slug | Full label |
|-------------|-------------|------------|
| Add dark mode support | `dark-mode-support` | `epic:dark-mode-support` |
| Update the CSV export pipeline | `csv-export-pipeline` | `epic:csv-export-pipeline` |
| Enhance authentication for SSO | `authentication-sso` | `epic:authentication-sso` |

Before any issues are filed, `/spec` shows the full plan and surfaces an editable line:

```
Epic label: epic:dark-mode-support
```

To change the slug, pick `Adjust plan` at the approval prompt and ask for a different label — `/spec` revises the `Epic label:` line and re-asks. The label shown is exactly what will be created and applied to every issue in the run. All `epic:<slug>` labels share color `#5319e7` (purple) and a description of `Belongs to epic: <epic title>`, giving them a consistent visual identity in GitHub and keeping the original title recoverable from the label.

An `epic:<slug>` label that already exists is never reused silently. On a full `/spec` run two checks fire, in order:

1. While `/catalog` provisions labels for the child batch, an existing label triggers a one-time `y/N` confirmation before it is applied to any issue in that batch.
2. Before the epic tracking issue is created, `/spec` re-checks and asks via `AskUserQuestion` — `Reuse existing label`, `Pick a different slug`, or `Cancel`. Picking a different slug loops back to plan editing and re-checks the new label.

A standalone `/catalog --epic <slug>` run only sees the first check.

## End-to-End Example

**Scenario**: You want to add dark-mode support to your app.

```
/spec add dark mode support
```

1. `/spec` interviews you: target platforms, toggle placement, persistence strategy.
2. It synthesizes a plan and shows it for approval:

   ```
   Goal: Ship a user-togglable dark mode backed by a persisted theme preference.
   
   Tasks:
     1. Add ThemeContext and useTheme hook
     2. Implement CSS variable switching in the root layout
     3. Persist preference to localStorage
     4. Add toggle button to the nav bar
   
   Epic label: epic:dark-mode-support
   ```

3. You approve (or pick `Adjust plan` and ask for a different `Epic label:`).
4. `/spec` delegates to `/catalog`, which files issues in priority order:

   | # | Title | Labels |
   |---|-------|--------|
   | #42 | Add ThemeContext and useTheme hook | `enhancement`, `priority:high`, `epic:dark-mode-support` |
   | #43 | Implement CSS variable switching in root layout | `enhancement`, `priority:high`, `epic:dark-mode-support` |
   | #44 | Persist theme preference to localStorage | `enhancement`, `priority:medium`, `epic:dark-mode-support` |
   | #45 | Add dark mode toggle to nav bar | `enhancement`, `priority:medium`, `epic:dark-mode-support` |

5. The epic tracking issue is filed last (so it can link to all children):

   | # | Title | Labels |
   |---|-------|--------|
   | #46 | epic: add dark mode support | `epic`, `epic:dark-mode-support`, `priority:high` |

   The epic body carries Goal, Background and Acceptance Criteria only — no
   issue checklist. Each child (#42–#45) is attached to #46 through GitHub's
   native sub-issues API, and any `Depends On` edge from the plan becomes a
   blocked-by relationship between the child issues.

All five issues share the `epic:dark-mode-support` label. Filtering by that label in GitHub shows the full scope of the epic at a glance.

## Assumptions & Conventions

- **Epic-last creation**: child issues are filed first so their numbers are known before the epic tracking issue is created. Each child is then attached to the epic as a native GitHub sub-issue — the epic body itself carries no checklist.
- **Approval gate**: `/spec` and `/catalog` both show a preview table and an approval prompt before filing anything. The exceptions are `/catalog --auto`, which files directly, and `/spec`'s full-path team-readiness step, which may file an extracted interface-contract issue and add `phase:*` labels without a further prompt.
- **`/catalog` is the implementation**: `/spec` delegates issue creation to `/catalog`. This means catalog settings (label provisioning and inference, consolidation, priority ordering) apply to spec-generated issues too.
- **Duplicate detection**: `/issue` checks for open issues with similar titles before filing, and surfaces potential duplicates for your review. `/catalog` does not — it files every approved row in the batch.
- **Epic label consistency**: all `epic:<slug>` labels share the same color and description convention, regardless of which skill created them.

## Pairing with Other Plugins

Speckit works on its own. The companion plugins referenced below are siblings in the [smallorbit-plugins](../../README.md#available-plugins) marketplace — install them separately to use the composed workflows.

Speckit defines the work; [swarmkit](../swarmkit) executes it:

```
/spec add CSV export              # Plan the feature, file issues
/swarm                            # Resolve them with parallel agents
```

Use `/speckit:interview` (or `/interview`) as a planning warm-up before `/spec` — arrive with clearer, grounded requirements. Use [sessionkit](../sessionkit)'s `/handoff` if a spec session runs long and needs to continue in a new context.
