---
name: handoff
description: Capture session context to a handoff document so another agent can take over seamlessly. Run it after every meaningful state change (PR opened, task completed, decision made) — delta mode keeps the cost trivial so you don't have to wait for context pressure.
triggers:
  - "/handoff"
  - "write a handoff"
  - "create handoff"
  - "save handoff"
  - "context is running low"
allowed-tools: Bash, Read, Write, TaskList, TaskGet, Skill, Agent
---

# Handoff

Capture the current session's goal, progress, git state, remaining work, and key context into `<working-dir>/.sessionkit/HANDOFF.md` so another agent can pick up without losing momentum.

Synthesis has three paths, picked automatically based on what's actually changed:

- **Delta mode** (no sub-agent, in-line surgical Edits) — the default fast path when a prior `HANDOFF.md` exists, its git fingerprint is an ancestor of HEAD, and only a handful of sections need updating. Median wall time well under 3s.
- **Full regenerate via Haiku sub-agent** — used when no prior file exists, the prior file is structurally divergent, drift exceeds the delta threshold, or `--full` is passed. Skips synthesis for sections whose fingerprints still match.
- **Both-fingerprints-match short-circuit** — if both fingerprints match, all four reusable sections come straight from the prior file and the sub-agent is skipped entirely (this case is unchanged from prior behavior).

## Input

`$ARGUMENTS` — optional freeform notes to fold into the handoff (e.g. "focus on the auth refactor, skip the docs work"). If omitted, auto-infer everything from session state.

Recognized flags (parsed from `$ARGUMENTS`):

- `--full` — force the full-regenerate Haiku path even if delta mode would otherwise apply. Use when you want a fresh narrative pass (e.g. Goal/Context have meaningfully drifted but the structural fingerprints haven't).

If `--full` is present, strip it from `$ARGUMENTS` before folding the remaining text into Goal/Context.

## Process

### 1. Gather context

Run these commands in parallel:

```bash
cat .claude/TODO 2>/dev/null || cat .claude/todos.md 2>/dev/null || echo "No todo file"
git rev-parse HEAD 2>/dev/null || echo "no-head"
git branch --show-current
git diff --cached --name-only
git diff --name-only
git log --oneline -5
git diff --cached
```

Also invoke `TaskList` to get all task IDs, then call `TaskGet` once per task ID to fetch full details. Collect every task that is **not** deleted (i.e. `status !== "deleted"`). This runs in parallel with the bash commands above.

### 1a. Compute change fingerprints

Build two short fingerprints used in step 1b to decide which sections to regenerate:

- `gitFingerprint` — `<HEAD-sha>:<sorted-staged-files-hash>:<sorted-unstaged-files-hash>`. A change in HEAD or in the working-tree file lists invalidates the Git State + Progress sections.
- `taskFingerprint` — SHA-1 of the canonicalized (sorted by `id`, fields stripped to `id,subject,status,blockedBy`) Task List JSON. Any change invalidates the Task List + Remaining Work sections.

Compute both in shell (e.g. `git rev-parse HEAD`, `printf %s "$json" | shasum -a 1 | cut -d' ' -f1`).

### 1b. Skip-unchanged check

If `.sessionkit/HANDOFF.md` already exists, Read it and look for an HTML comment header of the form:

```
<!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->
```

Compare against the fingerprints from step 1a using two **independent** reuse decisions — each fingerprint governs its own pair of sections, with no cross-coupling:

- If `gitFingerprint` matches the prior header: reuse `## Git State` and `## Progress` verbatim. Otherwise regenerate them.
- If `taskFingerprint` matches the prior header: reuse `## Task List` and `## Remaining Work` verbatim. Otherwise regenerate them.

`## Goal` and `## Context` are always refreshed (Goal also incorporates `$ARGUMENTS` when present).

If no prior file exists, or the meta header is absent, treat both fingerprints as non-matching and regenerate all sections.

When **both** fingerprints match, all four reusable sections come straight from the prior file. The routing decision is made in step 1c.

### 1c. Delta-mode decision

After step 1b classifies which sections need to be regenerated, decide whether to use the in-line **delta-mode** path or dispatch the Haiku sub-agent.

**Pick delta mode when ALL of these hold:**

1. A prior `.sessionkit/HANDOFF.md` exists and parsed cleanly in step 1b (meta header found, all six canonical sections present in the documented order, fenced `json` block in `## Task List` parses).
2. The prior `gitFingerprint`'s HEAD-sha component is an ancestor of the current HEAD — verify with `git merge-base --is-ancestor <prior-head-sha> HEAD` (exit 0 = ancestor). This confirms session continuity rather than a branch swap. (The staged/unstaged drift is already captured by step 1b's fingerprint comparison; this ancestor check only guards against branch-swap or force-push scenarios where the commit graph has diverged.)
3. At most **two** of the four reusable sections (`Git State`, `Progress`, `Task List`, `Remaining Work`) need regeneration. Goal and Context are always refreshed and don't count toward the threshold.
4. `$ARGUMENTS` does not contain `--full` and does not look like a structural-rewrite directive (a freeform note longer than ~200 chars or one that explicitly mentions reframing/rewriting the goal/context counts as structural — when in doubt, fall back to full regenerate).

**Otherwise, use the full Haiku regenerate path** (step 2).

Record the chosen mode (`delta` vs `full`) for the step 4 confirmation.

### 1d. Delta-mode mechanics (only when step 1c picked `delta`)

In delta mode, do **not** invoke the Agent tool. Instead, surgically Edit the existing `.sessionkit/HANDOFF.md`:

1. Always refresh `## Goal` and `## Context` in-line — synthesize new bullets directly from the conversation arc and the raw step-1 outputs (and `$ARGUMENTS` if present). Use the Edit tool, replacing the prior section bodies between their headings.
2. For each of the four reusable sections, regenerate only those flagged in step 1b:
   - `## Git State` — emit from the raw git outputs in step 1 using the template in step 2a.
   - `## Progress` — bullets from staged/unstaged file lists, recent commits, and any conversation signals about completed/decided/abandoned threads.
   - `## Task List` — serialize the Task List JSON exactly per the rules in step 2a.
   - `## Remaining Work` — bullets in priority order from the (refreshed or reused) Task List plus unfinished conversation threads.
3. Update the meta header in place: replace `gitFingerprint=<sha>` and `taskFingerprint=<sha>` with the values computed in step 1a, even if only one of them changed. Refresh the `**Date**` field.
4. Preserve byte-exact content of any reusable section that step 1b marked verbatim — do not touch its bullets, ordering, or whitespace.

The output of delta mode must be byte-equivalent (modulo touched sections and the meta-header / Date refresh) to what a full regenerate would have produced from the same inputs. `/pickup` parses both outputs identically — there is no parser-level distinction.

After all Edits land, skip step 2 entirely and proceed to step 3.

### 2. Synthesize via Haiku sub-agent

Reached only when step 1c picked the `full` path. Delegate markdown synthesis to a sub-agent running on Haiku — the handoff document is structured output and does not need the main model.

Invoke the `Agent` tool with:

- `subagent_type`: `"general-purpose"`
- `model`: `"claude-haiku-4-5"`
- `prompt`: a single message containing
  1. The fixed template from step 2a below.
  2. The conversation context summary (recent goal, decisions, gotchas — bullet form, no prose).
  3. The raw outputs from step 1 (git fingerprints, file lists, recent commits, todo file contents).
  4. The Task List JSON from step 1.
  5. For each section from step 1b: an explicit per-section directive of either `reuse verbatim` (with the existing content) or `regenerate`. List the four reusable sections (`Git State`, `Progress`, `Task List`, `Remaining Work`) with their directive; `Goal` and `Context` are always `regenerate`.
  6. `$ARGUMENTS` if present (with `--full` already stripped).
  7. Explicit instructions, including the verbatim contract:

     > "Sections marked `reuse verbatim` MUST be emitted byte-for-byte unchanged from the content provided — do not paraphrase, reorder, re-format, or re-wrap them. Generate fresh content ONLY for sections marked `regenerate`. Emit ONLY the markdown document. No commentary, no fences around the whole thing. Use bullets, not paragraphs, for Progress / Remaining Work / Context. Preserve the JSON code block for Task List exactly as given when reusing it verbatim."

**Timeout / failure handling**: if the Agent call fails, returns empty output, or produces output that does not contain the required `## Task List` heading, fall back to in-line synthesis. Prepend a single comment line to the document:

```
<!-- handoff-warning: haiku sub-agent unavailable, synthesized in-line -->
```

…and synthesize the document yourself using the same template.

### 2a. Strict template

The sub-agent (or in-line fallback) must emit exactly this structure. **Bullets only** in Progress / Remaining Work / Context — no narrative paragraphs. The meta header on line 1 is mandatory and is what step 1b reads on the next run.

```markdown
<!-- handoff-meta gitFingerprint=<sha> taskFingerprint=<sha> -->
# Handoff

**Project**: <working directory>
**Date**: <ISO date>
**Branch**: <current git branch>

## Goal
- <one bullet, one sentence>

## Progress
- <completed item>
- <decision made>
- <thread abandoned>

## Git State
- Branch: <branch>
- Staged: <list of staged files or "none">
- Unstaged: <list of unstaged files or "none">
- Recent commits (last 5):
  - <sha> <subject>

## Remaining Work
- <next step in priority order>
- <next step>

## Task List
```json
[
  {
    "id": "<task-id>",
    "subject": "<subject>",
    "description": "<description>",
    "activeForm": "<activeForm>",
    "status": "<status>",
    "blockedBy": [],
    "blocks": []
  }
]
```

## Context
- <key decision>
- <gotcha>
- <external reference>
```

Inference rules (applied by the sub-agent):

- **Goal** — one bullet derived from branch name, recent commits, and conversation arc.
- **Progress** — bullets only: what's been completed, decided, or abandoned this session.
- **Remaining Work** — bullets in priority order, drawn from the todo file and unfinished conversation threads.
- **Task List** — serialize the tasks from step 1 as a single fenced `json` code block. Array of task objects. Include only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, `blocks`. Exclude `owner`, `metadata`, and deleted tasks. Empty array `[]` if none. Preserve original task `id` so `/pickup` can wire `blockedBy` relationships.
- **Context** — bullets only: decisions, gotchas, dead ends, external references. Keep to what the next agent genuinely needs.

If `$ARGUMENTS` is provided, weave its guidance into Goal or Context.

### 3. Write to disk

Check `.gitignore` coverage first:

```bash
test -f .gitignore && grep -qE '^\.sessionkit/?$' .gitignore && echo "covered" || echo "not-covered"
```

- **`.gitignore` absent**: ask "No `.gitignore` found. Create one with `.sessionkit/` to keep handoff docs out of version control? (yes/no)". On yes, write `.gitignore` containing only `.sessionkit/`. On no, proceed.
- **`.gitignore` present but not covered**: ask "`.gitignore` doesn't cover `.sessionkit/`. Append it? (yes/no)". On yes, append `.sessionkit/` to `.gitignore`. On no, proceed.
- **Already covered**: proceed silently.

If `.sessionkit/HANDOFF.md` already exists, Read it first (the Write tool requires a prior Read of the target path). Step 1b already did this when a prior file exists.

Then create the directory if needed:

```bash
mkdir -p .sessionkit
```

- **Delta mode** (step 1d): the surgical Edits in step 1d already updated the file in place. Nothing more to do here beyond the `.gitignore` check above.
- **Full path** (step 2): Write the synthesized document to `.sessionkit/HANDOFF.md` using the Write tool, silently overwriting any existing file.

### 4. Confirm

Report the absolute path of the file written, the chosen mode and reuse outcome (e.g. `delta mode — refreshed Goal/Context, regenerated Git State + Progress`, `full regenerate — reused 2 sections (task)`, `full regenerate — regenerated all sections`), and suggest:

> Start a new session and run `/pickup` to resume.

## Constraints

- Section order in HANDOFF.md is fixed: Goal → Progress → Git State → Remaining Work → Task List → Context
- `.sessionkit/HANDOFF.md` in the working directory is the canonical location — never write elsewhere
- Legacy HANDOFFs that lack a `## Task List` or meta header remain valid inputs to `/pickup` — their absence is not an error (the next run will simply regenerate everything)
