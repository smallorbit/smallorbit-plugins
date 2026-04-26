---
name: init
description: Initialize squadkit in the current repository. Interview-driven wizard that captures verify/install/baseBranch commands and writes .squadkit/config.json at the repo root. No per-stack presets — the user supplies every command directly.
triggers:
  - "/squadkit:init"
  - "init squadkit"
  - "set up squadkit"
  - "configure squadkit"
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Squadkit Init

Interview the user, then write `.squadkit/config.json` at the repo root. The config captures the four commands every downstream squadkit skill (role contracts, spawn-team, retro) reads instead of hardcoding stack-specific tooling.

## Input

`$ARGUMENTS` — ignored. The skill is fully interview-driven.

## Process

### 1. Resolve the repo root

Squadkit always writes to the **main repo root**, never to a worktree. Use the git common dir to find it:

```bash
COMMON=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "ERROR: not inside a git repository" >&2; exit 1; }
case "$COMMON" in
  /*) ;;
  *)  COMMON="$PWD/$COMMON" ;;
esac
REPO_ROOT=$(cd "$(dirname "$COMMON")" && pwd)
CONFIG_PATH="$REPO_ROOT/.squadkit/config.json"
echo "REPO_ROOT=$REPO_ROOT"
echo "CONFIG_PATH=$CONFIG_PATH"
```

`git rev-parse --git-common-dir` returns the path to the shared `.git` directory, which always sits at the main repo root — even when invoked from inside a worktree where `.git` is a file pointer.

### 2. Refuse to overwrite without confirmation

If `$CONFIG_PATH` already exists, Read it and surface its current contents to the user, then ask via `AskUserQuestion`:

- **Question**: `.squadkit/config.json already exists at <path>. Overwrite it?`
- **Options**:
  - `Overwrite` — proceed with the interview.
  - `Cancel` — abort the skill with no changes.

If the user picks `Cancel`, exit with a one-line message naming the existing file and stop. Do not continue to step 3.

### 3. Interview

Ask each question via `AskUserQuestion`. **No stack presets, no auto-detection** — the user types the exact command. An empty answer is valid for `verify.typecheck`, `verify.test`, and `install` (treated as "this repo has no such step"). For `baseBranch`, default to `develop` if the user accepts the default.

Ask the four questions sequentially, surfacing the running config back to the user after each answer so they see what's accumulated.

| # | Field | Question | Default |
|---|-------|----------|---------|
| 1 | `verify.typecheck` | `Command to run for type checking? (e.g. \`npm run typecheck\`, \`mypy .\`, \`cargo check\`. Empty = no typecheck step.)` | none |
| 2 | `verify.test` | `Command to run the test suite? (e.g. \`npm test\`, \`pytest\`, \`cargo test\`. Empty = no test step.)` | none |
| 3 | `install` | `Command to install dependencies in a fresh worktree? (e.g. \`npm install\`, \`pip install -e .\`. Empty = no install step.)` | none |
| 4 | `baseBranch` | `Default base branch for PRs opened by squad members?` | `develop` |

Trim whitespace from every answer. Treat the literal string `develop` as the accepted default if the user confirms question 4 without typing.

### 4. Write the config

Assemble the JSON object:

```json
{
  "verify": {
    "typecheck": "<answer-1>",
    "test": "<answer-2>"
  },
  "install": "<answer-3>",
  "baseBranch": "<answer-4>"
}
```

Create the directory and write the file (pretty-printed, two-space indent, trailing newline):

```bash
mkdir -p "$REPO_ROOT/.squadkit"
```

Then use the `Write` tool with `$CONFIG_PATH` as the absolute path. If the file already existed (step 2 confirmed overwrite), Read it first so Write accepts the overwrite.

### 5. Confirm

Print:

- The absolute path written.
- The full JSON contents.
- A one-line next step:

> Squadkit is initialized. Edit `.squadkit/config.json` directly to tweak commands later, or rerun `/squadkit:init` to redo the interview.

## Constraints

- Never write to a worktree's `.squadkit/`. The config lives once, at the main repo root, found via `git rev-parse --git-common-dir`.
- Never apply per-stack presets or auto-detect package managers. Every command comes from the user via `AskUserQuestion`.
- Never overwrite an existing `.squadkit/config.json` without explicit confirmation through `AskUserQuestion`.
- Empty strings are valid answers for `verify.typecheck`, `verify.test`, and `install`. Downstream skills treat empty as "skip this step."
- `baseBranch` defaults to `develop` but is not validated against the remote — accept whatever the user provides.
- The config is a four-field schema. Do not invent additional fields here; future role contracts will extend the schema in their own releases.
