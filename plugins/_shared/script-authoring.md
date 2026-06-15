# Skill Script Authoring Standard

Shell scripts extract deterministic, stateless bash work from skills to reduce model round-trips. This document is the single source of truth for the convention. Skills that ship scripts reference this document instead of inventing local rules.

## When to extract

Extract bash work into a script when it is:

- **Deterministic and stateless** — the same inputs always produce the same outputs; no judgment required.
- **Multi-step within a single turn** — several tool calls that the model would otherwise execute sequentially (fetch → parse → validate → emit) collapse into one script invocation.
- **Meaningfully round-trip-reducing** — typically 3+ bash turns eliminated per call. Single-command wrappers are not worth extracting.

Do not extract logic that requires model reasoning, branching on ambiguous input, or interacting with the user.

## Folder layout

Scripts live under the skill's own directory, never in a shared scripts folder:

```
plugins/<plugin>/skills/<skill>/scripts/<script-name>.sh
```

There is no `_shared/scripts/` directory. Each skill owns its scripts. This keeps the skill self-contained and avoids cross-skill coupling.

## `$SKILL_DIR` resolution

When a skill installs via the plugin marketplace, its files live in the plugin cache — not at `plugins/<plugin>/skills/<skill>/` relative to the consumer repo. The harness emits the runtime-resolved absolute path in a header line at the top of each skill invocation:

```
Base directory for this skill: <absolute path>
```

Capture this into a shell variable before invoking any script:

```bash
export SKILL_DIR="<absolute path from the 'Base directory for this skill:' header line>"
```

Use `"$SKILL_DIR/scripts/<name>.sh"` for every invocation. Never hardcode `plugins/<plugin>/...` — that path only resolves in repos that vendor the plugin directly.

### Cross-skill invocation

The default expectation is that a script is invoked **only by its owner skill**, where `$SKILL_DIR` aligns and the standard `"$SKILL_DIR/scripts/<name>.sh"` form works. Some sub-skills (e.g. `flowkit:push-or-pr`) are intentionally shared across multiple callers; those callers cannot use their own `$SKILL_DIR` to address the script. Two resolution patterns cover the cases that come up in this repo:

- **Sibling-skill caller** (caller and target are in the same plugin) — derive the target's `SKILL_DIR` from the caller's:

  ```bash
  TARGET_SKILL_DIR="$(dirname "$SKILL_DIR")/<target-skill>"
  bash "$TARGET_SKILL_DIR/scripts/<name>.sh" ...
  ```

- **Project-local caller** (e.g. a skill under `.claude/skills/` reaching into a vendored `plugins/<plugin>/skills/<skill>/`) — hardcode the repo-relative path. This is the one case where the "never hardcode `plugins/<plugin>/...`" rule does not apply, because project-local skills only ever run in repos that vendor the target plugin:

  ```bash
  bash plugins/<plugin>/skills/<target-skill>/scripts/<name>.sh ...
  ```

Either way, document the cross-skill dependency in the target's SKILL.md so callers know how to invoke it. The allowlist implications are addressed under [`.claude/settings.json` allowlist](#claudesettingsjson-allowlist) below.

## JSON output convention

On success a script exits 0 and emits a **bare payload** JSON object on stdout. No envelope wrapper — the payload is the output:

```json
{"key": "value", "count": 3, "items": [...]}
```

Do **not** use an `{ok, data, error}` envelope. The calling skill reads the raw fields directly.

- The schema must be stable. Adding optional fields is fine; removing or renaming fields is a breaking change.
- Use `jq -n` with `--arg` / `--argjson` / `--slurpfile` to construct the output. Do not echo raw JSON strings.

## Error convention

On failure a script:

1. Exits with a **non-zero exit code**.
2. Emits a human-readable error message to **stderr**.
3. Emits **nothing to stdout** (leaves stdout empty).

The calling skill surfaces stderr to the user and stops. Scripts must never emit partial JSON on stdout when they fail.

```bash
echo "script-name: what went wrong and why" >&2
exit 1
```

Use exit code `1` for runtime failures, `2` for invalid arguments.

## Canonical example

`plugins/swarmkit/skills/swarm/scripts/preflight.sh` — collapses git fetch, base-branch verification, and `gh` auth check into one call. Its output is a bare JSON object; errors go to stderr with non-zero exit. Refer to it and the other scripts in that directory as the reference implementation.

## Smoke tests

Every skill that ships scripts also ships a `scripts/test.sh` smoke test alongside them:

```
plugins/<plugin>/skills/<skill>/scripts/test.sh
```

`test.sh` exercises every script in the same `scripts/` directory and asserts the contract documented above:

1. **Invalid-argument invocations** — for each script, drive at least one invalid-argument case (unknown flag, missing required value, wrong arity, malformed positional) and assert:
   - exit code is non-zero,
   - stdout is empty,
   - stderr is non-empty.
2. **Successful invocations** — where a script can be invoked deterministically without external network or destructive side effects (e.g. with empty input arrays that short-circuit, or read-only inspection commands), assert:
   - exit code is 0,
   - stdout is parseable JSON (`jq -e .`),
   - the JSON object exposes every documented top-level key (`jq -e 'has("...")'`).

Scripts that always require live network or destructive state changes (live `gh` calls, `git fetch origin`, `git checkout`) cannot be exercised on their happy path from a smoke harness — limit those to invalid-argument coverage. Document that limitation in the test header so reviewers understand the scope.

A test failure must surface a clear, line-grep-able message (`FAIL [<script> <case>]: ...`) and exit non-zero. Reference implementations:

- `plugins/swarmkit/skills/swarm/scripts/test.sh` — argument-validation-only coverage for network-dependent scripts.
- `plugins/swarmkit/skills/clean-worktrees/scripts/test.sh` — argument validation plus read-only / empty-input happy paths.

### Top-level runner

The repo-root runner discovers and executes every skill's `test.sh`:

```bash
bash scripts/test-all-skill-scripts.sh
```

It walks `plugins/*/skills/*/scripts/test.sh`, runs each with the test directory as CWD, and exits non-zero if any test fails. This is the single entry point intended for CI.

This runner is the **L1 gate** in `.github/workflows/skills-ci.yml` — it runs as a required check on every PR touching `plugins/**`. A script-backed skill with no `test.sh`, or whose `test.sh` fails, blocks merge. See [`evals/README.md`](../../evals/README.md) for the full eval-layer overview (L1 script tests, L2 skill-doc lint).

## `.claude/settings.json` allowlist

The harness requires explicit permission before executing each script path. Add an entry to the project `.claude/settings.json` allowlist when introducing a new script:

```json
{
  "permissions": {
    "allow": [
      "Bash($SKILL_DIR/scripts/my-script.sh:*)"
    ]
  }
}
```

Because `$SKILL_DIR` resolves at runtime, use the literal token `$SKILL_DIR` in the allowlist string — Claude Code expands environment variables in permission patterns. Add one entry per script, in the same PR that introduces the script. Do not batch allowlist entries ahead of the scripts they cover.

### Allowlist for cross-skill scripts

The harness expands `$SKILL_DIR` in allowlist patterns against the **calling skill's** runtime `$SKILL_DIR`. That means `Bash($SKILL_DIR/scripts/<name>.sh:*)` only matches when the script is invoked by its owner — for cross-skill scripts (see [Cross-skill invocation](#cross-skill-invocation) above), that pattern silently fails to match every external caller.

Use these two matchers instead:

```json
{
  "permissions": {
    "allow": [
      "Bash(plugins/<plugin>/skills/<target-skill>/scripts/<name>.sh:*)",
      "Bash(*/plugins/<plugin>/skills/<target-skill>/scripts/<name>.sh:*)"
    ]
  }
}
```

- The first matches project-local callers that invoke via the repo-relative path.
- The second is a leading-glob suffix matcher that catches callers from other plugins' skills, where the script is invoked via an absolute path that varies by install location (plugin marketplace cache, vendored copy, etc.).

Both are additions on top of the standard `$SKILL_DIR` form; if the script is also invoked by its owner, keep that entry too. The path itself acts as the discriminator — the script's plugin-namespaced location is distinctive enough that the suffix glob does not over-match.
