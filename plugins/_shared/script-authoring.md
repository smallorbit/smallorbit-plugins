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

`plugins/swarmkit/skills/x-swarm/scripts/preflight.sh` — collapses git fetch, base-branch verification, and `gh` auth check into one call. Its output is a bare JSON object; errors go to stderr with non-zero exit. Refer to it and the other scripts in that directory as the reference implementation.

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
