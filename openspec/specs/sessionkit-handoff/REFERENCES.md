# Handoff — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `smallorbit-plugins/`.
Line numbers verified on 2026-05-23.

---

## Requirement: Context collection

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:37-50` — Step 1 runs git commands in parallel and calls `TaskList` + `TaskGet` per task "in parallel with the bash commands above"

### Scenario: Context gathered
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:37-50` — "Run these commands in parallel."
**Interpolated; no direct test.**

---

## Requirement: Fingerprint-based section reuse

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:52-77` — Steps 1a and 1b define fingerprint computation and the two-independent-decision reuse logic

### Scenario: Git fingerprint matches
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:69-70` — "If `gitFingerprint` matches the prior header: reuse `## Git State` and `## Progress` verbatim."
**Interpolated; no direct test.**

### Scenario: Task fingerprint matches
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:71-72` — "If `taskFingerprint` matches the prior header: reuse `## Task List` and `## Remaining Work` verbatim."
**Interpolated; no direct test.**

### Scenario: Both fingerprints match
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:74-77` — "When both fingerprints match, all four reusable sections come straight from the prior file."
**Interpolated; no direct test.**

---

## Requirement: Routing to delta or full path

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:79-108` — Step 1c defines the four delta conditions and the routing decision

### Scenario: Delta path selected
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:84-88` — all four conditions enumerated; "Pick delta mode when ALL of these hold."
**Interpolated; no direct test.**

### Scenario: Full path selected
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:90` — "Otherwise, use the full Haiku regenerate path."
**Interpolated; no direct test.**

---

## Requirement: Document structure

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:140-188` — Step 2a defines the strict template including section order and inference rules
- `plugins/sessionkit/skills/handoff/SKILL.md:229-230` — Constraints: "Section order in HANDOFF.md is fixed: Goal → Progress → Git State → Remaining Work → Task List → Context"

### Scenario: Section order
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:229` — fixed section order constraint.
**Interpolated; no direct test.**

### Scenario: Bullet-only sections
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:141` — "Bullets only in Progress / Remaining Work / Context — no narrative paragraphs."
**Interpolated; no direct test.**

---

## Requirement: Task list serialization

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:193-195` — inference rule for Task List: "Include only `id`, `subject`, `description`, `activeForm`, `status`, `blockedBy`, `blocks`. Exclude `owner`, `metadata`, and deleted tasks… Preserve original task `id`."

### Scenario: Task list in JSON block
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:168-182` — template shows fenced `json` block; `plugins/sessionkit/skills/handoff/SKILL.md:193-195` — serialization rules.
**Interpolated; no direct test.**

---

## Requirement: Sub-agent synthesis

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:111-136` — Step 2 defines the Haiku sub-agent invocation and the failure fallback with warning comment

### Scenario: Sub-agent succeeds
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:114-128` — Agent tool call with model `"claude-haiku-4-5"`.
**Interpolated; no direct test.**

### Scenario: Sub-agent fails
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:130-135` — "if the Agent call fails, returns empty output, or produces output that does not contain the required `## Task List` heading, fall back to in-line synthesis."
**Interpolated; no direct test.**

---

## Requirement: Gitignore coverage

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:201-213` — Step 3 defines the three-branch `.gitignore` check

### Scenario: Gitignore absent
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:206-207` — "`.gitignore` absent: ask 'No `.gitignore` found…'"
**Interpolated; no direct test.**

### Scenario: Gitignore present but uncovered
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:208-209` — "`.gitignore` present but not covered: ask '`.gitignore` doesn't cover `.sessionkit/`…'"
**Interpolated; no direct test.**

### Scenario: Already covered
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:210` — "Already covered: proceed silently."
**Interpolated; no direct test.**

---

## Requirement: Canonical output location

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:231` — Constraints: "`.sessionkit/HANDOFF.md` in the working directory is the canonical location — never write elsewhere"

### Scenario: Document written
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:15` — "into `<working-dir>/.sessionkit/HANDOFF.md`".
**Interpolated; no direct test.**

---

## Requirement: Completion report

**Sources**
- `plugins/sessionkit/skills/handoff/SKILL.md:224-226` — Step 4 defines what to report: path, mode, reuse outcome, and `/pickup` suggestion

### Scenario: Handoff confirmed
**Source:** `plugins/sessionkit/skills/handoff/SKILL.md:224-226` — verbatim step 4 text.
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. All scenarios are **interpolated from the SKILL.md directive** — no test suite exists for handoff behavior.
2. The `gitFingerprint` ancestor check (`git merge-base --is-ancestor`) is distinct from the section reuse decision — it guards against branch-swap scenarios, not just content drift.
3. The "at most two reusable sections" delta threshold is an implementation detail that is not observable from outside the skill; it is captured in the spec as an approximation of the routing intent.
4. The strict template at step 2a is the canonical source of truth for section order — the constraint at line 229 restates it.
