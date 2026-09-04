---
name: spec-baseline-roadmap
description: Survey a codebase for the capabilities that deserve an OpenSpec baseline, diff against what's already specified, and produce an approved task chain to baseline everything and reconcile the result. Planning only — does not write any spec files itself. Use when the user wants to baseline an entire app/codebase comprehensively, not just one capability.
triggers:
  - "baseline the whole app"
  - "baseline this entire codebase"
  - "spec out the whole app"
  - "roadmap for baselining"
  - "what still needs a spec"
  - "comprehensive spec baseline"
allowed-tools: Read, Glob, Grep, Bash, TaskCreate, TaskUpdate, TaskList, AskUserQuestion
---

# Spec Baseline Roadmap

Plan a full OpenSpec baseline of a codebase: survey it for capabilities, identify which
ones already have a spec, and produce a task chain — one task per uncovered capability
(each a self-contained delegation brief for a fresh baseliner agent), plus a final
cross-spec consistency review task. This skill only plans; it never writes a spec file
and never spawns a baseliner agent itself. The complement to `/spec-baseline` (which does
one capability) and `/tighten-to-spec` (which audits an existing spec against its
implementation).

## When to use this vs. the alternatives

| Situation | Skill |
|---|---|
| One capability, already known | `/spec-baseline` |
| A spec already exists; check it still matches the code | `/tighten-to-spec` |
| "Baseline the whole app" / unclear how many specs are needed | `/spec-baseline-roadmap` (this skill) |

---

## Process

### Step 1 — Survey for capabilities

Read the target repo's structure (source tree, test files, docs, README) and identify
every distinct *capability* worth its own spec — a cohesive unit of behavior with its own
requirements and scenarios, not a file or a class. Use these signals:

- A named subsystem with its own test file(s) or test suite section
- A documented contract between components (producer/consumer, client/server, plugin
  boundary) — these are highest-value since another party depends on them
- A schema or config format other code/consumers read
- A user-facing interaction flow (UI screen, CLI command, API endpoint) with rules about
  what's shown/accepted/rejected
- A cross-cutting lifecycle (install/build/deploy, startup/shutdown sequencing)

Split by cohesion, not by file: a capability can span multiple files (e.g. a writer +
observer + docs file that together define one queue contract), and a large file can hold
multiple capabilities if they're independently understandable. Aim for capabilities a
reviewer could audit standalone — if describing one requires constantly cross-referencing
another, they're probably the same capability.

For each candidate capability, note: a proposed kebab-case slug, one-sentence purpose,
the primary source files, the test file(s) that pin its behavior, and a rough size
(small/medium/large) based on file count and behavioral complexity.

### Step 2 — Diff against what's already specified

Check for existing specs: look for `openspec/specs/*/spec.md` (or wherever this repo's
OpenSpec directory lives — check for a `scripts/openspec` validator and an `openspec/`
directory; if neither exists, none of the codebase is baselined yet). List which
candidate capabilities from Step 1 already have a spec, which are partially covered, and
which have none. Only the uncovered/partial ones go into the roadmap.

### Step 3 — Check baseline tooling exists

Confirm `scripts/openspec` (the validator script) and `openspec/README.md` exist in this
repo. If not, the first task in the roadmap must be provisioning them — copy from
wherever this org's canonical copy lives (ask the user if unknown; do not fabricate a
validator). Do not assume a real npm/CLI "OpenSpec" package is needed — `/spec-baseline`
validates against a small self-contained bash script, not an external CLI.

### Step 4 — Build the task chain

For each uncovered capability, create one task:

- **subject**: `Baseline <slug> spec`
- **description**: A full delegation brief for a fresh agent with no context on this
  conversation — it must stand alone. Include: the capability slug; what it covers and
  its boundaries (what's explicitly OUT of scope because another planned or existing spec
  owns it — list sibling capability slugs to avoid duplicate ownership); the exact files
  to read and in what order (implementation first, tests second, git log third for the
  "why"); whether to write `REFERENCES.md` (default: skip for code the user wrote and
  knows well, produce for legacy/unfamiliar/high-stakes code — ask the user if unclear);
  the stack-agnostic constraint (no framework/class names in the spec body; literal
  field names, constants, config keys, and defaults ARE required); the exact validate
  command (`bash scripts/openspec validate <slug> --type spec --strict`); a grep command
  tailored to that capability's stack terms to catch leaked framework names; and a request
  to report back the validator output, the grep result, the ordered requirement heading
  list, and anything left out because the sources didn't support it.
- **activeForm**: `Baselining <slug> spec`

Assign a model per task by size/complexity: small well-documented capabilities → Sonnet;
medium-to-large or ambiguous/judgment-heavy ones → Opus. State your reasoning briefly.

Wire dependencies only where real: most baseline tasks are independent and should run in
parallel (no `blockedBy` between them). Add a `blockedBy` edge only when one capability's
spec is a prerequisite for another to reference correctly (e.g. a popover spec that must
cross-reference a capture spec's field-visibility rules should block on that capture spec
existing first).

Add exactly one final task after all baseline tasks:

- **subject**: `Cross-spec consistency review and fixes`
- **description**: Full brief for a fresh Opus agent: read every `openspec/specs/*/spec.md`
  in full; find and fix (a) duplicated requirements describing the same behavior in two
  specs — pick the natural owner (whichever spec's Purpose statement covers it most
  directly) and make others cross-reference it by requirement name instead of restating
  it; (b) contradicting constants/allowed-values between specs; (c) vocabulary drift (the
  same concept named differently across specs — standardize on whichever spec was written
  first/most carefully, noting exceptions); (d) coverage gaps — grep test file header
  comments against spec content and report (don't necessarily fix) any test-pinned
  behavior with no owning spec; (e) re-run the stack-agnostic grep across all specs to
  catch anything reintroduced. After edits, re-validate every capability with `--strict`
  and report a full pass/fail list, a one-line-per-change summary, and the gap list.
  Do not create new spec files for gaps — report them for a follow-up decision.
- **blockedBy**: every baseline task above.

### Step 5 — Present and confirm

Show the plan as a compact list (slug → purpose → model → blocked-by), the dependency
shape if non-trivial, and ask the user to approve before creating any tasks or spawning
any agent — everything up to this point is planning only.

On approval, create the tasks (`TaskCreate`/`TaskUpdate`) and offer to drive them
(spawning one agent per baseline task, verifying each report by re-running its validate +
grep commands yourself before marking the task complete, same for the final cross-spec
task) or hand the list back for the user to run manually.

## Constraints

- **Planning only.** This skill never writes a spec file and never spawns a baseliner
  agent on its own — task creation and driving happen only after explicit approval.
- **Don't invent capabilities the code doesn't support.** Every candidate must trace to a
  real subsystem, test file, or documented contract — not a hoped-for future structure.
- **Don't assume a real OpenSpec CLI is required.** The validator is the bash script that
  ships alongside `/spec-baseline`; check for `scripts/openspec` before assuming anything
  is missing.
- **One roadmap per invocation.** If the survey turns up capabilities that clearly belong
  to unrelated subsystems the user may want to baseline separately (e.g. a monorepo with
  multiple independent apps), ask which to plan rather than merging them into one chain.
- **Delegation briefs must be self-contained.** A fresh agent receiving a baseline task
  has no memory of this conversation — the description must carry every file path, scope
  boundary, and decision the survey already made.

## Output checklist

- [ ] Every candidate capability classified: specced / partial / uncovered
- [ ] Baseline tooling (`scripts/openspec`, `openspec/README.md`) confirmed present, or a
      provisioning task added
- [ ] One task per uncovered capability, each a self-contained delegation brief with model
      assignment and rationale
- [ ] Dependencies wired only where a real ordering constraint exists
- [ ] Exactly one final cross-spec consistency review task, blocked by all baseline tasks
- [ ] Plan presented and approved before any task was created
