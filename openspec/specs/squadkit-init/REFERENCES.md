# squadkit-init — Source References

Companion to [spec.md](./spec.md). Not part of the OpenSpec spec.
Paths relative to `<repo-root>/`.
Line numbers verified on 2026-05-24.

---

## Requirement: Main Repo Root Resolution

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:24-38` — Step 1 "Resolve the repo root" walks through `git rev-parse --git-common-dir`, the absolute-path normalization fallback, and assignment of `REPO_ROOT` / `CONFIG_PATH`.
- `plugins/squadkit/skills/init/SKILL.md:103` — Constraint reiterating "Never write to a worktree's `.squadkit/`".

**Notes**
- No automated test. The contract is enforced by the SKILL.md prose and a single git command at the top of the wizard.

### Scenario: Worktree caller writes to main root
**Source:** `plugins/squadkit/skills/init/SKILL.md:38` — explanatory line "`git rev-parse --git-common-dir` returns the path to the shared `.git` directory, which always sits at the main repo root — even when invoked from inside a worktree where `.git` is a file pointer."
**Interpolated; no direct test.**

### Scenario: Non-repo invocation aborts
**Source:** `plugins/squadkit/skills/init/SKILL.md:27` — the bash one-liner `COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "ERROR: not inside a git repository" >&2; exit 1; }` fails fast when outside a repo.
**Interpolated; no direct test.**

---

## Requirement: Overwrite Confirmation

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:40-49` — Step 2 specifies the confirmation prompt and the two-option `AskUserQuestion`.
- `plugins/squadkit/skills/init/SKILL.md:105` — Constraint: "Never overwrite an existing `.squadkit/config.json` without explicit confirmation through `AskUserQuestion`."

### Scenario: Existing config triggers confirmation
**Source:** `plugins/squadkit/skills/init/SKILL.md:42-47` — "If `$CONFIG_PATH` already exists, Read it and surface its current contents to the user, then ask via `AskUserQuestion`" with the `Overwrite` / `Cancel` options.
**Interpolated; no direct test.**

### Scenario: Cancel preserves existing config
**Source:** `plugins/squadkit/skills/init/SKILL.md:49` — "If the user picks `Cancel`, exit with a one-line message naming the existing file and stop. Do not continue to step 3."
**Interpolated; no direct test.**

---

## Requirement: Interview-Only Input

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:51-65` — Step 3 "Interview" lists the five questions and reiterates "**No stack presets, no auto-detection** — the user types the exact command."
- `plugins/squadkit/skills/init/SKILL.md:104` — Constraint: "Never apply per-stack presets or auto-detect package managers. Every command comes from the user via `AskUserQuestion`."

### Scenario: Five sequential questions
**Source:** `plugins/squadkit/skills/init/SKILL.md:55-63` — the numbered table enumerates the five fields in order; line 55 specifies "Ask the five questions sequentially, surfacing the running config back to the user after each answer".
**Interpolated; no direct test.**

### Scenario: Whitespace trimmed
**Source:** `plugins/squadkit/skills/init/SKILL.md:65` — "Trim whitespace from every answer."
**Interpolated; no direct test.**

---

## Requirement: Optional and Empty Fields

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:53` — "An empty answer is valid for `verify.typecheck`, `verify.test`, `verify.lint`, and `install` (treated as 'this repo has no such step')."
- `plugins/squadkit/skills/init/SKILL.md:65` — "Omit `verify.lint` from the written JSON entirely if the user leaves it blank — the field is optional and downstream roles check for its presence before using it."
- `plugins/squadkit/skills/init/SKILL.md:106-107` — Constraints reinforcing the empty-string-vs-omit distinction for `verify.lint`.

### Scenario: Empty verify or install step persisted as empty string
**Source:** `plugins/squadkit/skills/init/SKILL.md:106` — "Empty strings are valid answers for `verify.typecheck`, `verify.test`, and `install`. Downstream skills treat empty as 'skip this step.'"
**Interpolated; no direct test.**

### Scenario: Blank lint key omitted
**Source:** `plugins/squadkit/skills/init/SKILL.md:107` — "`verify.lint` is optional. Omit the key entirely when the user leaves it blank rather than writing an empty string — downstream roles check for its presence."
**Interpolated; no direct test.**

---

## Requirement: Default Base Branch

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:53` — "For `baseBranch`, default to `develop` if the user accepts the default."
- `plugins/squadkit/skills/init/SKILL.md:63` — table row showing `baseBranch` default `develop`.
- `plugins/squadkit/skills/init/SKILL.md:108` — Constraint: "`baseBranch` defaults to `develop` but is not validated against the remote — accept whatever the user provides."

### Scenario: Default accepted
**Source:** `plugins/squadkit/skills/init/SKILL.md:65` — "Treat the literal string `develop` as the accepted default if the user confirms question 5 without typing."
**Interpolated; no direct test.**

### Scenario: Custom value accepted verbatim
**Source:** `plugins/squadkit/skills/init/SKILL.md:108` — constraint confirms no remote validation; user-supplied value is accepted as-is.
**Interpolated; no direct test.**

---

## Requirement: Config File Format

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:67-89` — Step 4 "Write the config" shows the JSON template, the `mkdir -p` for the `.squadkit` directory, and the directive to use `Write` with `$CONFIG_PATH` "pretty-printed, two-space indent, trailing newline".
- `plugins/squadkit/skills/init/SKILL.md:109` — Constraint: "The config is a four-field schema. Do not invent additional fields here".

### Scenario: Directory created when missing
**Source:** `plugins/squadkit/skills/init/SKILL.md:85-87` — bash block running `mkdir -p "$REPO_ROOT/.squadkit"` before the Write call.
**Interpolated; no direct test.**

### Scenario: JSON shape
**Source:** `plugins/squadkit/skills/init/SKILL.md:71-81` — JSON template showing the top-level shape with `verify`, `install`, and `baseBranch` keys; lines 69 and 109 reinforce that no other fields are written.
**Interpolated; no direct test.**

---

## Requirement: Confirmation Output

**Sources**
- `plugins/squadkit/skills/init/SKILL.md:91-99` — Step 5 "Confirm" enumerates the absolute path, JSON contents, and the next-step line directing the operator to manual edits or rerunning `/squadkit:init`.

### Scenario: Post-write summary
**Source:** `plugins/squadkit/skills/init/SKILL.md:93-99` — the bulleted list and the verbatim "Squadkit is initialized. Edit `.squadkit/config.json` directly to tweak commands later, or rerun `/squadkit:init` to redo the interview." line.
**Interpolated; no direct test.**

---

## Cross-cutting interpretive notes

1. **No automated tests for this skill.** The squadkit init wizard is documented entirely through `SKILL.md` prose; no harness exercises the bash steps or the `AskUserQuestion` flow. Every scenario above is interpolated from the SKILL.md directives.
2. **Stack-agnostic by construction.** The spec deliberately avoids naming any package manager or build tool because the SKILL.md treats every command as opaque operator input.
3. **Schema lock at four fields.** Line 109's constraint "Do not invent additional fields here" is the only enforcement preventing schema drift; downstream role contracts are expected to extend the schema in their own releases.
