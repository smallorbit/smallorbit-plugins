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

### 2. Refuse to overwrite without confirmation

If `$CONFIG_PATH` already exists, Read it and surface its current contents to the user, then ask via `AskUserQuestion`:

- **Question**: `.squadkit/config.json already exists at <path>. Overwrite it?`
- **Options**:
  - `Overwrite` — proceed with the interview.
  - `Cancel` — abort the skill with no changes.

If the user picks `Cancel`, exit with a one-line message naming the existing file and stop. Do not continue to step 3.

### 3. Interview

Ask each question via `AskUserQuestion`. **No stack presets, no auto-detection** — the user types the exact command. An empty answer is valid for `verify.typecheck`, `verify.test`, `verify.lint`, and `install` (treated as "this repo has no such step"). For `baseBranch`, default to `develop` if the user accepts the default.

Ask the five questions sequentially, surfacing the running config back to the user after each answer so they see what's accumulated.

| # | Field | Question | Default |
|---|-------|----------|---------|
| 1 | `verify.typecheck` | `Command to run for type checking? (e.g. \`npm run typecheck\`, \`mypy .\`, \`cargo check\`. Empty = no typecheck step.)` | none |
| 2 | `verify.test` | `Command to run the test suite? (e.g. \`npm test\`, \`pytest\`, \`cargo test\`. Empty = no test step.)` | none |
| 3 | `verify.lint` | `Command to run the linter? (e.g. \`npm run lint\`, \`ruff check\`, \`cargo clippy\`. Optional — empty = no lint step. The reviewer uses this to scope errors to PR-touched files.)` | none |
| 4 | `install` | `Command to install dependencies in a fresh worktree? (e.g. \`npm install\`, \`pip install -e .\`. Empty = no install step.)` | none |
| 5 | `baseBranch` | `Default base branch for PRs opened by squad members?` | `develop` |

Trim whitespace from every answer. Treat the literal string `develop` as the accepted default if the user confirms question 5 without typing; for any other value of `baseBranch`, accept what the operator provides verbatim — do not validate it against the remote. Omit `verify.lint` from the written JSON entirely if the user leaves it blank — the field is optional and downstream roles check for its presence before using it.

### 4. Write the config

Assemble the JSON object. Include `verify.lint` only when the user provided a non-empty answer:

```json
{
  "verify": {
    "typecheck": "<answer-1>",
    "test": "<answer-2>",
    "lint": "<answer-3>"
  },
  "install": "<answer-4>",
  "baseBranch": "<answer-5>"
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
