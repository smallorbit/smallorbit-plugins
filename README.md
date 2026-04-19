# smallorbit-plugins

[![smallorbit-plugins landing page](docs/assets/landing-hero.png)](https://smallorbit.github.io/smallorbit-plugins/)

## From idea to release. With you in the loop.

Claude Code plugins for plan, execute, and ship — each keeping you at the handoffs that matter.

**[→ View the full landing page](https://smallorbit.github.io/smallorbit-plugins/)**

## Setup

```
/plugin marketplace add smallorbit/smallorbit-plugins
```

## Available Plugins

### Development Lifecycle

| Plugin | Install | Description |
|--------|---------|-------------|
| **speckit** | `/plugin install speckit@smallorbit-plugins` | Define and capture work through interviews and issue filing |
| **swarmkit** | `/plugin install swarmkit@smallorbit-plugins` | Resolve GitHub issues with parallel worktree agents. See [METHODOLOGY.md](./plugins/swarmkit/METHODOLOGY.md) for the stacked agent/PR workflow in depth. For the experimental Agent Teams-based `/squad` variant, see [plugins/swarmkit/SETUP.md](./plugins/swarmkit/SETUP.md). |
| **polishkit** | `/plugin install polishkit@smallorbit-plugins` | Critique code quality, sweep for cruft, and eliminate dead code |
| **flowkit** | `/plugin install flowkit@smallorbit-plugins` | Manage the full git lifecycle from branch to release |
| **sessionkit** | `/plugin install sessionkit@smallorbit-plugins` | Session continuity, context handoffs, and meta-learning |

### Utilities & Productivity

| Plugin | Install | Description |
|--------|---------|-------------|
| **vaultkit** | `/plugin install vaultkit@smallorbit-plugins` | Obsidian vault skills — read, search, edit notes, and capture decisions |

## Getting Started

A short walkthrough that takes you from idea to shipped change using `/spec` and `/swarm` — the two kits at the heart of the workflow.

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and signed in
- [GitHub CLI](https://cli.github.com/) authenticated (`gh auth status` should return green)
- A GitHub repository you can push to
- A `develop` branch on that repo (swarmkit targets it by default)

### 1. Install speckit and swarmkit

These two are the essential kits to start with — speckit plans the work, swarmkit resolves it. Install both from the marketplace:

```
/plugin install speckit@smallorbit-plugins
/plugin install swarmkit@smallorbit-plugins
```

### 2. Plan the feature with `/spec`

Say you're building a small notes app and want to add tags to notes. Kick off an interview:

```
/spec add tags to notes
```

`/spec` reads your codebase first, then asks focused questions to pin the feature down:

> **Claude:** Notes are stored in `notes.ts` with `id`, `title`, and `body` fields. Where should tags attach — on each note, or in a separate collection?
>
> **You:** On each note. One note can have many tags.
>
> **Claude:** Should tags be free-form strings the user types, or chosen from a controlled list?
>
> **You:** Free-form for now.
>
> **Claude:** Where should tags surface in the UI — inside `ui/NoteEditor.tsx`, a sidebar, both?
>
> **You:** Both. Edit tags in the editor, filter from the sidebar.

…a few rounds later, after nailing down persistence, filter UX, and the migration story, `/spec` shows the plan for approval and — on your OK — files it:

```
Filed epic: #101 Epic: Add tags to notes             label: epic:tags-notes
Filed children:
  #102 Extend Note schema with tags field            priority:high   type:feature
  #103 Add tag input to NoteEditor                   priority:high   type:feature
  #104 Render tag chips on note cards                priority:medium type:feature
  #105 Filter notes by tag from the sidebar          priority:medium type:feature
```

### 3. Resolve the epic with `/swarm`

Swarm the child issues in parallel:

```
/swarm 102 103 104 105
```

swarmkit spawns one isolated-worktree agent per issue, each on its own `worktree-agent-<n>` branch. Agents work concurrently, commit with conventional-commit messages, and open stacked PRs:

```
Swarm complete — 4 PRs opened:

  #210 feat(notes): extend Note schema with tags field        → develop
  #211 feat(notes): add tag input to NoteEditor               → worktree-agent-102
  #212 feat(notes): render tag chips on note cards            → worktree-agent-103
  #213 feat(notes): filter notes by tag from the sidebar      → worktree-agent-104

Stack root: #210. Run /merge-stack to land top-down.
```

### 4. Ship it

Once the PRs look right:

```
/merge-stack     # merge all swarm PRs top-down into develop
/cut             # create a release candidate from develop
/release         # promote to main, tag the release, close referenced issues
```

Or collapse all three into a single `/ship`. See the [flowkit README](./plugins/flowkit/README.md) for the full lifecycle, RC naming, and staging support.

### What's next

- **polishkit** — run `/critique`, `/tidy-codebase`, and `/dead-code` as a quality gate before shipping.
- **sessionkit** — use `/handoff` when a spec or swarm session outgrows one context, and `/skillit` to capture patterns worth keeping.
- **vaultkit** — drop decisions and notes into an Obsidian vault alongside the work.

Each plugin's README goes deeper. For the stacked-PR mental model behind `/swarm`, read [swarmkit's METHODOLOGY](./plugins/swarmkit/METHODOLOGY.md).

## How the Plugins Compose

The development-lifecycle plugins form a complete loop from idea to release:

```
/interview     → clarify the idea (speckit)
/spec          → plan the feature, file issues (speckit)
/swarm         → resolve issues with parallel agents (swarmkit)
/critique      → assess quality; /tidy-codebase to clean up (polishkit)
/release       → ship merged work to production (flowkit)
```

**polishkit** sits between `/swarm` and `/release` as a quality gate: use `/critique` to assess elegance and craft, `/tidy-codebase` to sweep for stale files and cruft, and `/dead-code` to eliminate unused exports before shipping.

**sessionkit** acts as connective tissue throughout: use `/handoff` to preserve state across agent context limits, `/skillit` to capture reusable patterns after a swarm, and `/suggest-permissions` to reduce approval friction over time.

**vaultkit** lives outside the loop — it's a utility for capturing decisions, notes, and archives into an Obsidian vault alongside any work, dev or otherwise. Requires Obsidian and the Obsidian CLI.

Each plugin's README describes how it pairs with the others.

See each plugin's README for detailed usage.

## License

MIT — see [LICENSE](./LICENSE).
