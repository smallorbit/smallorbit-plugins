# Speckit

A Claude Code plugin for defining and capturing work. Interview a feature into existence, bulk-convert findings into issues, or quickly file a single issue — all from slash commands.

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
| **catalog** | `/catalog` | Bulk-converts findings (from a code review, audit, or assessment) into prioritized, labeled GitHub issues. |
| **issue** | `/issue` | Quickly drafts and files a single GitHub issue from a description. Checks for duplicates and previews before creating. |

### Sub-Skills (internal)

| Skill | Used by | Purpose |
|-------|---------|---------|
| **catalog** | `/spec` | Creates the child issues and epic after plan approval. Invoked automatically — no need to run it separately unless converting standalone findings. |

## Typical Workflows

### Spec out a feature

```
/spec add dark mode support       # Interview → plan → epic + issues
```

### Turn a code review into a backlog

```
/catalog                          # Pick up findings from earlier in the conversation
/catalog findings.md              # Or point at a file
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

## How Issue Works

`/issue` is the lightweight path. Give it a description, and it drafts a title, infers type and priority, checks for duplicates, and shows a preview before filing. Use it when you know exactly what to file and don't need an interview.

## Assumptions & Conventions

- **Epic-last creation**: child issues are filed first so their numbers are known before the epic tracking issue is created. The epic body then contains a full checklist of child issue links.
- **Approval gate**: no issues are ever created without your explicit approval. `/spec` and `/catalog` both show a preview table before filing anything.
- **`/catalog` is the implementation**: `/spec` delegates issue creation to `/catalog`. This means catalog settings (duplicate detection, label inference, priority ordering) apply to spec-generated issues too.
- **Duplicate detection**: before filing any issue, `/catalog` and `/issue` check for open issues with similar titles. Potential duplicates are surfaced for your review before creation proceeds.

## Pairing with Other Plugins

Speckit defines the work; [swarmkit](../swarmkit) executes it:

```
/spec add CSV export              # Plan the feature, file issues
/swarm                            # Resolve them with parallel agents
```

Use `/speckit:interview` (or `/interview`) as a planning warm-up before `/spec` — arrive with clearer, grounded requirements. Use [sessionkit](../sessionkit)'s `/handoff` if a spec session runs long and needs to continue in a new context.
