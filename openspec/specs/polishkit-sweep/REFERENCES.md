# Sweep — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `repo-root/`.
Line numbers verified on 2026-05-22.

---

## Requirement: Scope intake

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:24-31` — `## Scope` section defines the three scope forms: path/glob, category hint, empty (full sweep)
- `plugins/polishkit/skills/sweep/SKILL.md:35-36` — "Phases are independent — if scope restricts to one, skip the other."

### Scenario: Full sweep (no scope)
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:26-27` — "Empty — run everything."
**Interpolated; no direct test.**

### Scenario: Path or glob scope
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:28-29` — "A path or glob (`src/components/`, `**/*.test.ts`) — restricts both phases to that subtree."
**Interpolated; no direct test.**

### Scenario: Category hint scope
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:30-31` — "A category hint (`dead-code-only`, `cruft-only`, `git-only`) — runs just the matching phase."
**Interpolated; no direct test.**

---

## Requirement: Dead code detection

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:39-47` — `#### 1.1 Detect language and available tools` — TypeScript/JavaScript, Python, Go detection commands
- `plugins/polishkit/skills/sweep/SKILL.md:49-95` — `#### 1.2 Scan for dead code` — per-language scan commands for unused exports, imports, dead variables, commented-out code
- `plugins/polishkit/skills/sweep/SKILL.md:86-90` — exclusion list: node_modules/, dist/, build/, .next/, generated files (*.generated.ts, *.d.ts), test files

**Notes**
- The test-file exclusion rationale is stated explicitly: "dead code in tests can be intentional fixtures"

### Scenario: TypeScript project scanned
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:63-68` — ts-prune for unused exports; `plugins/polishkit/skills/sweep/SKILL.md:72-73` — tsc --noEmit for noUnusedLocals/noUnusedParameters.
**Interpolated; no direct test.**

### Scenario: Test files excluded
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:89-90` — "Test files (dead code in tests can be intentional fixtures)" in the exclusion list.
**Interpolated; no direct test.**

---

## Requirement: Cruft detection

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:105-165` — `### Phase 2 — Cruft & Hygiene` — full set of parallel checks
- `plugins/polishkit/skills/sweep/SKILL.md:107-112` — stale documentation checks
- `plugins/polishkit/skills/sweep/SKILL.md:113-117` — build artifacts and dead directories
- `plugins/polishkit/skills/sweep/SKILL.md:118-123` — documentation gaps
- `plugins/polishkit/skills/sweep/SKILL.md:124-127` — duplicate content
- `plugins/polishkit/skills/sweep/SKILL.md:129-164` — git hygiene including the remote merged-branch classification loop

**Notes**
- The remote merged-PR branch classification was added in commit `d7f7836` (docs: cover remote merged PR branches). Prior to that commit only local branch hygiene was covered.
- The `parked/*` prefix exemption in the remote branch filter is an implicit convention in this repo.

### Scenario: Remote branch classification
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:133-151` — the bash loop that fetches, lists non-default/non-parked branches, and classifies each by PR state using `gh pr list`.
**Interpolated; no direct test.**

### Scenario: Only merged-PR branches proposed for deletion
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:153-161` — the deletion policy table: MERGED → propose deletion; CLOSED / OPEN / NO PR → preserve.
**Interpolated; no direct test.**

---

## Requirement: Remote branch deletion safety

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:162-165` — "When deleting, **always use the disambiguated refspec form** (`git push origin :refs/heads/<branch>`). The unqualified `git push origin --delete <branch>` fails with `src refspec matches more than one` whenever a same-named tag exists"
- `plugins/polishkit/skills/sweep/SKILL.md:164-167` — batch form: `git push origin :refs/heads/branch-a :refs/heads/branch-b`

**Notes**
- The motivation is explicit: the `rc/YYYY-MM-DD.N` tag shape from `flowkit:cut` is the canonical collision case. This was added in commit `d7f7836`.

### Scenario: Single remote branch deletion
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:162-163` — disambiguated refspec instruction.
**Interpolated; no direct test.**

### Scenario: Multiple remote branch deletions
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:165-167` — batch push form shown explicitly.
**Interpolated; no direct test.**

---

## Requirement: Interactive confirmation

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:168-181` — `### 3. Present findings and confirm each action` — combined Remove/Update/Keep summary, AskUserQuestion batching at most 4, grouping related items, wait-for-all-answers before step 4
- `plugins/polishkit/skills/sweep/SKILL.md:176-180` — specific AskUserQuestion call conventions: batch ≤4, group related, default first option to recommended

### Scenario: Confirmation collected before execution
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:181` — "Wait for all answers before proceeding to step 4."
**Interpolated; no direct test.**

### Scenario: Question batching
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:175` — "Use `AskUserQuestion` to confirm each proposed action, batched in groups of at most 4 questions per call."
**Interpolated; no direct test.**

---

## Requirement: Cleanup execution and commit

**Sources**
- `plugins/polishkit/skills/sweep/SKILL.md:182-191` — `### 4. Execute cleanup` — apply, tsc verify, re-run project verify, commit message `chore: sweep codebase`, PR targeting base branch with develop-then-default fallback

### Scenario: Post-removal parse check
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:184-185` — "For dead-code removals, verify the file still parses — run `tsc --noEmit` or the language equivalent if available."
**Interpolated; no direct test.**

### Scenario: Commit and PR opened
**Source:** `plugins/polishkit/skills/sweep/SKILL.md:187-191` — "Commit with `chore: sweep codebase` and open a PR targeting the project's base branch (auto-detect `develop` then fall back to `main`)."
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **No test coverage exists for any scenario.** Sweep has no test suite. All scenarios are interpolated from the skill's prompt instructions.

2. **Remote branch deletion safety was retroactively added.** The disambiguated refspec requirement was introduced in commit `d7f7836` specifically to prevent collisions with `rc/YYYY-MM-DD.N` tags created by `flowkit:cut`. Any revision to the sweep skill that touches the deletion path must preserve this form.

3. **"Cruft detection" PR base branch fallback is simpler than polish's.** Sweep uses a two-step fallback (`develop` then repo default) without reading any git config keys. This is intentional — sweep is a maintenance operation that targets the integration branch directly rather than requiring explicit base configuration.

4. **Parked branch exemption is implied, not documented inline.** The remote branch filter excludes `^(develop|main|gh-pages|parked/.*)$` — the `parked/*` prefix is an implicit repo convention not explained in the skill prose. A reviewer should verify this is the correct set of protected branch patterns for this repo.

5. **Phase independence is stated but not enforced programmatically.** The skill says "Phases are independent — if scope restricts to one, skip the other," but there is no guard preventing both phases from running when a category hint is given. This is a behavioral claim interpolated from prose, not from any gate condition in the code.
