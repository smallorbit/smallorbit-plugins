# Polish — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `repo-root/`.
Line numbers verified on 2026-05-22.

---

## Requirement: Scope intake

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:27-43` — `## Input` section defines the three accepted scope forms (path, glob, cross-cutting concern) and the `--model`, `--agent`, `--max-files`, `--base`, `--dry-run` flags
- `plugins/polishkit/skills/polish/SKILL.md:47-59` — `### 1. Resolve scope` specifies enumerate-and-pass-verbatim for path/glob, theme+boundary decomposition for concern, and the slug derivation
- `plugins/polishkit/skills/polish/SKILL.md:42-43` — empty-scope prompt text: `"What scope should I polish? (path, glob, or cross-cutting concern + scope hint)"`

**Notes**
- The "pass file list verbatim" contract is explicit ("Pass the resolved file list to the agent verbatim so it doesn't re-discover scope")

### Scenario: Path or glob scope provided
**Source:** `plugins/polishkit/skills/polish/SKILL.md:47-49` — "For a path/glob, list files that match." and the verbatim-pass instruction.
**Interpolated; no direct test.**

### Scenario: Cross-cutting concern scope provided
**Source:** `plugins/polishkit/skills/polish/SKILL.md:49-50` — "For a cross-cutting concern, treat the description as the agent's *theme* and the path/glob hint as the *file boundary* — pass both to the agent."
**Interpolated; no direct test.**

### Scenario: No scope provided
**Source:** `plugins/polishkit/skills/polish/SKILL.md:42-43` — the inline prompt string shown when `<scope>` is empty.
**Interpolated; no direct test.**

---

## Requirement: Verify command detection

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:61-75` — `### 2. Detect the project's verify commands` specifies the full priority order (CLAUDE.md → package.json → Makefile → language defaults) and the ask-user fallback
- `plugins/polishkit/skills/polish/SKILL.md:73-74` — "If nothing matches, ask the user for the verify command before dispatching. Never invent a command the repo doesn't expose."

**Notes**
- Watch-mode exclusion is explicit: "Skip watch-mode scripts"

### Scenario: Verify command found in package.json
**Source:** `plugins/polishkit/skills/polish/SKILL.md:67-69` — package.json scripts detection priority list: typecheck, test:run, test, lint.
**Interpolated; no direct test.**

### Scenario: No verify command detectable
**Source:** `plugins/polishkit/skills/polish/SKILL.md:73-74` — explicit ask-user fallback when nothing matches.
**Interpolated; no direct test.**

---

## Requirement: PR base branch resolution

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:77-118` — `### 3. Resolve the PR base branch` — full 5-step resolution chain with inline bash pseudocode
- `plugins/polishkit/skills/polish/SKILL.md:83-90` — step 1 (explicit `--base` arg extraction)
- `plugins/polishkit/skills/polish/SKILL.md:92-94` — step 2 (`claude.polishkit.prBase`)
- `plugins/polishkit/skills/polish/SKILL.md:96-99` — step 3 (`claude.flowkit.prBase` courtesy interop)
- `plugins/polishkit/skills/polish/SKILL.md:101-105` — step 4 (develop if on remote)
- `plugins/polishkit/skills/polish/SKILL.md:107-113` — step 5 (repo default with warning)
- `plugins/polishkit/skills/polish/SKILL.md:116` — "The agent must use it for both the branch cut **and** the `gh pr create --base` argument."

**Notes**
- The flowkit interop is explicitly labeled best-effort: "The flowkit read at step 3 is best-effort interop only — polishkit works without flowkit installed."
- This chain was introduced in commit `3469b50` (fix: resolve PR base via flowkit chain) and the canonical spec was extracted in `8a61f87` (refactor: extract canonical base-resolution spec)

### Scenario: Explicit --base overrides all config
**Source:** `plugins/polishkit/skills/polish/SKILL.md:83-90` — step 1 bash block checks for `--base` first before any config read.
**Interpolated; no direct test.**

### Scenario: Polishkit config key present
**Source:** `plugins/polishkit/skills/polish/SKILL.md:92-94` — step 2 reads `claude.polishkit.prBase`.
**Interpolated; no direct test.**

### Scenario: Fallback to develop
**Source:** `plugins/polishkit/skills/polish/SKILL.md:101-105` — step 4 checks `git ls-remote --heads origin develop`.
**Interpolated; no direct test.**

### Scenario: Fallback to repo default with warning
**Source:** `plugins/polishkit/skills/polish/SKILL.md:107-113` — step 5 uses `gh repo view` for default branch and echoes warning to stderr.
**Interpolated; no direct test.**

---

## Requirement: Isolated single-agent dispatch

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:122-131` — `### 4. Dispatch the subagent` specifies `subagent_type: general-purpose`, `isolation: worktree`, `mode: bypassPermissions`, `run_in_background: true`
- `plugins/polishkit/skills/polish/SKILL.md:186-187` — constraint: "One agent per invocation, one PR per agent. Never fan out multiple polish agents on the same scope."

**Notes**
- The `run_in_background: true` is the source of the "orchestrator does not block" behavior

### Scenario: Agent dispatched
**Source:** `plugins/polishkit/skills/polish/SKILL.md:126-130` — Agent tool call shape with all four parameters specified.
**Interpolated; no direct test.**

---

## Requirement: Semantic fix application

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:136-143` — `**TASK**` section defines the three review heuristic categories: Reuse, Quality, Efficiency
- `plugins/polishkit/skills/polish/SKILL.md:144-146` — "For a cross-cutting theme, prioritize fixes matching that theme; deprioritize everything else (mention as deferred findings, don't fix)."
- `plugins/polishkit/skills/polish/SKILL.md:147-149` — `**RESPECT BEHAVIOR**` clause: public surfaces stay compatible; behavior-changing fixes go to deferred findings section

### Scenario: Theme-filtered pass
**Source:** `plugins/polishkit/skills/polish/SKILL.md:144-146` — explicit theme priority instruction with deferred-findings disposition.
**Interpolated; no direct test.**

### Scenario: Public contract preserved
**Source:** `plugins/polishkit/skills/polish/SKILL.md:147-149` — "keep public surfaces compatible. If a fix would change a public contract, leave it untouched and surface in the PR's `## Findings deferred to issues` section with file:line refs."
**Interpolated; no direct test.**

---

## Requirement: File cap enforcement

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:35-36` — `--max-files <N>` input flag definition with default of 15
- `plugins/polishkit/skills/polish/SKILL.md:150-152` — `**SOFT CAP**` clause specifying cap behavior and deferred-findings disposition for excess
- `plugins/polishkit/skills/polish/SKILL.md:187-188` — constraint restating the cap philosophy: "if scope is so large the agent wants to touch >50 files, it should narrow"

### Scenario: Scope within cap
**Source:** `plugins/polishkit/skills/polish/SKILL.md:150` — implicit: cap only activates when exceeded.
**Interpolated; no direct test.**

### Scenario: Scope exceeds cap
**Source:** `plugins/polishkit/skills/polish/SKILL.md:150-152` — "If the scope clearly exceeds the cap, fix the highest-impact subset and list the rest under deferred findings."
**Interpolated; no direct test.**

---

## Requirement: Green-build gate

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:157-158` — workflow step 4: "Verify by running every command in `VERIFY_COMMANDS`... All MUST pass before push. If any fails, iterate until green or revert the breaking edit and list it as deferred."
- `plugins/polishkit/skills/polish/SKILL.md:194` — constraint: "Verify must be green before push. Red builds are never acceptable, even for 'lightweight' passes."

### Scenario: All verify commands pass
**Source:** `plugins/polishkit/skills/polish/SKILL.md:157-158` — "All MUST pass before push."
**Interpolated; no direct test.**

### Scenario: Verify command fails after an edit
**Source:** `plugins/polishkit/skills/polish/SKILL.md:158` — "If any fails, iterate until green or revert the breaking edit and list it as deferred."
**Interpolated; no direct test.**

---

## Requirement: Single PR delivery

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:159-160` — workflow step 5: push and open PR with `--base "$BASE_BRANCH"` explicitly; warning about omitting `--base`
- `plugins/polishkit/skills/polish/SKILL.md:162-170` — `**PR BODY SHAPE**` clause defining the canonical four-section structure including the extra `## Findings deferred to issues`
- `plugins/polishkit/skills/polish/SKILL.md:172-175` — `**NO-OP IS LEGITIMATE**` clause: "if the pass finds nothing actionable in the scope, open the PR anyway"

### Scenario: Fixes applied and verified
**Source:** `plugins/polishkit/skills/polish/SKILL.md:159-160` — push and PR creation step, explicit `--base` requirement.
**Interpolated; no direct test.**

### Scenario: No actionable fixes found
**Source:** `plugins/polishkit/skills/polish/SKILL.md:172-175` — "open the PR anyway with `## Summary` stating `no actionable simplifications found`"
**Interpolated; no direct test.**

---

## Requirement: Dry-run mode

**Sources**
- `plugins/polishkit/skills/polish/SKILL.md:38-39` — `--dry-run` flag definition in `## Input`
- `plugins/polishkit/skills/polish/SKILL.md:177-179` — `### 5. Dry-run mode`: "the agent skips the apply/commit/push phase and instead returns a structured findings report inline (not as a PR)"

### Scenario: Dry-run invocation
**Source:** `plugins/polishkit/skills/polish/SKILL.md:177-179` — dry-run mode definition.
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **No test coverage exists for any scenario.** The SKILL.md is entirely prompt-based instruction; there is no test suite for polishkit skills. Every scenario in the spec is interpolated from the skill's written instructions rather than verified by an automated assertion.

2. **"Isolated worktree" guarantee is structural, not tested.** The `isolation: worktree` parameter on the Agent call is the mechanism — the spec says the agent MUST run in a worktree, but whether the harness enforces this is outside the skill's own control.

3. **Base-resolution chain order for flowkit interop.** The chain was authored with flowkit absent as a valid state. The courtesy read of `claude.flowkit.prBase` at step 3 is intentionally placed after polishkit's own key — this ordering was a deliberate product decision (commit `3469b50`, `8a61f87`).

4. **No-op PR is the defined termination condition.** Polish explicitly rejects "manufactured churn" — the no-op PR is a first-class outcome, not a degenerate case. This is a behavioral commitment worth reviewing against any future changes to the skill.
