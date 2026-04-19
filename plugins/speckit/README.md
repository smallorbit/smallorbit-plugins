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

`/spec` runs a structured interview using `AskUserQuestion` (1–4 questions per round), grounding each question in the actual codebase before asking. It continues until all ambiguities are resolved, then synthesizes a plan with goal, background, requirements, out-of-scope boundaries, and a task breakdown. The plan is shown for approval before any issues are filed.

Child issues are created via `/catalog`. An epic tracking issue is created last, after all child issue numbers are known. No issues are ever created without your explicit approval.

## How Catalog Works

`/catalog` accepts findings from three sources (checked in order): explicit input in `$ARGUMENTS`, findings from earlier in the conversation, or a file path. It parses them into discrete issues, checks for existing duplicates and labels, shows a summary table for approval, then creates all issues in priority order (high first).

You can pass `--epic <slug>` to scope all created issues to an existing epic label:

```
/catalog --epic dark-mode
```

This attaches the `epic:dark-mode` label to every issue created in that run, without re-running the full `/spec` interview.

Pass `--auto` to skip the approval gate and proceed directly to issue creation. Use this for programmatic or scripted invocations (e.g. `/polish`, CI pipelines) where interactive confirmation is not needed. Omit it for interactive use when you want to review and adjust the catalog before anything is filed.

## How Issue Works

`/issue` is the lightweight path. Give it a description, and it drafts a title, infers type and priority, checks for duplicates, and shows a preview before filing. Use it when you know exactly what to file and don't need an interview.

## Epic Labeling

When `/spec` produces a plan, it derives an `epic:<slug>` label and applies it to the epic tracking issue and every child issue. This makes the epic and all its work filterable in GitHub's issue list with a single label query.

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

You can change the slug at this point — edit the line and confirm. The label shown is exactly what will be created and applied to every issue in the run. All `epic:<slug>` labels share color `#5319e7` (purple) and a description of `Belongs to epic: <epic title>`, giving them a consistent visual identity in GitHub and keeping the original title recoverable from the label.

If a label named `epic:<slug>` already exists in the repository, `/spec` surfaces a warning before proceeding:

```
⚠ Label epic:dark-mode-support already exists.
  Use it, or edit the Epic label line above to choose a different slug.
```

You can accept the existing label (issues will simply receive it) or rename the slug before confirming the plan.

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

3. You confirm (or edit the `Epic label:` line).
4. `/spec` delegates to `/catalog`, which files issues in priority order:

   | # | Title | Labels |
   |---|-------|--------|
   | #42 | Add ThemeContext and useTheme hook | `priority:high`, `type:feature`, `epic:dark-mode-support` |
   | #43 | Implement CSS variable switching in root layout | `priority:high`, `type:feature`, `epic:dark-mode-support` |
   | #44 | Persist theme preference to localStorage | `priority:medium`, `type:feature`, `epic:dark-mode-support` |
   | #45 | Add dark mode toggle to nav bar | `priority:medium`, `type:feature`, `epic:dark-mode-support` |

5. The epic tracking issue is filed last (so it can link to all children):

   | # | Title | Labels |
   |---|-------|--------|
   | #46 | Epic: Add dark mode support | `type:epic`, `epic:dark-mode-support` |

   The epic body contains a checklist:
   ```
   - [ ] #42 Add ThemeContext and useTheme hook
   - [ ] #43 Implement CSS variable switching in root layout
   - [ ] #44 Persist theme preference to localStorage
   - [ ] #45 Add dark mode toggle to nav bar
   ```

All five issues share the `epic:dark-mode-support` label. Filtering by that label in GitHub shows the full scope of the epic at a glance.

## Assumptions & Conventions

- **Epic-last creation**: child issues are filed first so their numbers are known before the epic tracking issue is created. The epic body then contains a full checklist of child issue links.
- **Approval gate**: no issues are ever created without your explicit approval. `/spec` and `/catalog` both show a preview table before filing anything.
- **`/catalog` is the implementation**: `/spec` delegates issue creation to `/catalog`. This means catalog settings (duplicate detection, label inference, priority ordering) apply to spec-generated issues too.
- **Duplicate detection**: before filing any issue, `/catalog` and `/issue` check for open issues with similar titles. Potential duplicates are surfaced for your review before creation proceeds.
- **Epic label consistency**: all `epic:<slug>` labels share the same color and description convention, regardless of which skill created them.

## Pairing with Other Plugins

Speckit defines the work; [swarmkit](../swarmkit) executes it:

```
/spec add CSV export              # Plan the feature, file issues
/swarm                            # Resolve them with parallel agents
```

Use `/speckit:interview` (or `/interview`) as a planning warm-up before `/spec` — arrive with clearer, grounded requirements. Use [sessionkit](../sessionkit)'s `/handoff` if a spec session runs long and needs to continue in a new context.
