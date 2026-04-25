# Swarmkit — Agent Teams setup for `/x-squad`

**Official docs**: [Agent Teams on code.claude.com](https://code.claude.com/docs/en/agent-teams)

> **Experimental**: `/x-squad` is one of swarmkit's experimental skills (the `x-` prefix marks experimental commands across this plugin). Expect rougher edges than `/swarm`. The underlying Agent Teams API is itself experimental, so its surface and behavior may also change without notice.

`/x-squad` is swarmkit's Agent Teams-based variant of `/swarm`. It requires the Agent Teams API to be enabled via the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable. This document is the canonical setup guide for turning it on.

## Enable `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

Pick one of the three methods below. The variable must be set to `1` (or any non-empty value) in the environment Claude Code runs in.

### Method 1 — Shell export (bash/zsh)

Add the export to your shell profile (`~/.bashrc`, `~/.zshrc`, or equivalent) so every new shell session picks it up:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Reload the shell (`source ~/.zshrc`) or open a new terminal, then start Claude Code as usual.

### Method 2 — Claude Code `settings.json`

Set it under the `env` block of your Claude Code settings file (`~/.claude/settings.json` for global, or `.claude/settings.json` in a project for scoped):

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Claude Code will export the variable into its own process environment on startup.

### Method 3 — Per-invocation inline

Set the variable only for a single Claude Code invocation, leaving your global environment untouched:

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
```

Useful for one-off trials of `/x-squad` without committing to a persistent shell or settings change.

## Verify it's working

With the variable set, run `/x-squad` inside Claude Code. Its preflight check reads the environment and lets the skill continue. For example:

```
/x-squad 12 15 18
```

If the variable is **unset or empty**, the preflight aborts immediately with this exact message:

```
Agent Teams API is not enabled.

Run: export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

Then re-run this skill.
```

Seeing that message means the variable did not reach Claude Code's process — re-check the method above you chose (shell profile loaded? `settings.json` parsed? inline prefix attached to the right command?) and try again.
