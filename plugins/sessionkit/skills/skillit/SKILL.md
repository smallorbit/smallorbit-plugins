---
name: skillit
description: Evaluate the current session's activities and pinpoint potential new skills to develop. Reviews existing skills for overlap and offers to create or modify one.
triggers:
  - "/skillit"
  - "what skills did we develop"
  - "could this be a skill"
  - "identify new skills from this session"
  - "save this as a skill"
  - "turn this into a skill"
allowed-tools: AskUserQuestion, Read, Glob, Grep, Write, Edit
---

# Skillit

Reflect on the current session and identify reusable patterns worth encoding as skills. Reviews the existing skill library to avoid duplication, then offers to create a new skill or improve an existing one.

## Process

### 1. Reflect on the session

Review the conversation history for:

- Repeated instructions or corrections the user gave Claude
- Workflows that were executed step-by-step that could be automated
- Heuristics or rules applied consistently
- Tools or command sequences invoked in a fixed pattern
- Anything the user said "always do this" or "next time, remember to..."

Identify at least one candidate pattern.

### 2. Survey existing skills

Scan the skill library for potential overlap:

```bash
find ~/.claude/skills -name "SKILL.md" 2>/dev/null
find .claude/skills -name "SKILL.md" 2>/dev/null
find ~/.claude/commands -name "*.md" 2>/dev/null
```

Read the `name` and `description` front matter of any candidates that seem relevant. Surface any close matches to the user before proposing something new.

### 3. Present findings

For each candidate skill identified, describe:

- **What it would do** — one sentence
- **Why it's worth encoding** — what friction it removes
- **Overlap risk** — does it duplicate or extend an existing skill?

Then offer the user a choice:

> I found [N] potential skill(s). Options:
> 1. Create new skill: `<name>` — <description>
> 2. Modify existing skill: `<name>` — extend to cover <gap>
> 3. Skip — not worth encoding yet

### 4. Generate the skill file

On user agreement, create the skill file at the path they specify (or prompt for one):

```
~/.claude/skills/<name>/SKILL.md          # user-global
.claude/skills/<name>/SKILL.md            # project-local
```

The skill file must include:
- Front matter: `name`, `description`, `triggers` (at least two), `allowed-tools`
- A clear ## Process section with numbered steps
- A ## Constraints section listing hard rules

### 5. Confirm

Report the absolute path of the file written. Suggest running `/skillit` again at the end of future sessions to keep the library growing.

## Constraints

- Identify at least one candidate before concluding — never report "nothing found"
- Never create a skill file without user approval
- Always check for existing skills before proposing something new
- Skill names must be lowercase kebab-case
