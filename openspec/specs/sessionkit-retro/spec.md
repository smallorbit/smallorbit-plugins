# Retro

## Purpose
Retro runs a lightweight session retrospective. It scans four input surfaces — conversation transcript, task list, git activity, and hook/tool-denial events — then produces an inline summary and a one-keystroke action menu that delegates findings to the appropriate downstream skills.

## Requirements

### Requirement: Parallel signal collection
Retro SHALL gather all raw signals in parallel: git activity (recent commits, branch, stash, open PRs), session JSONL files (tool-denial and hook-blocked events), task list (all non-deleted tasks), and conversation transcript. Missing or empty surfaces SHALL be tolerated without error.

#### Scenario: All surfaces available
- **WHEN** all four input surfaces are accessible
- **THEN** Retro collects them in parallel and proceeds to synthesis

#### Scenario: A surface is unavailable
- **WHEN** one or more surfaces are missing or empty
- **THEN** Retro treats absence as a signal (e.g. no tool denials = no friction of that type) and continues

### Requirement: Three-bucket synthesis
Retro SHALL organize findings into exactly three sections: **What went well** (2–5 bullets), **What didn't go well** (2–5 bullets or the explicit empty-state line), and **Recommended actions** (1–4 items). Every finding SHALL cite concrete evidence — a turn, PR number, file name, or task subject. Retro SHALL NOT emit vague critique.

#### Scenario: Friction observed
- **WHEN** one or more friction signals are found (repeated corrections, hook blocks, failed commands, stalled tasks)
- **THEN** each is included in "What didn't go well" with a concrete citation

#### Scenario: No friction observed
- **WHEN** no friction signals are found across all surfaces
- **THEN** Retro emits the explicit empty-state line "No friction observed this session." in "What didn't go well"

#### Scenario: Positive patterns found
- **WHEN** cleanly executed workflows or early-caught mistakes are found
- **THEN** at least one bullet appears in "What went well" even for low-friction sessions

### Requirement: Recommended actions with delegation targets
Retro SHALL map each friction signal or repeatable pattern to a downstream delegation target. Recommended actions SHALL be capped at 4. The 4th slot SHALL be reserved for "Other — I'll handle this manually" when more than 3 actionable items exist.

#### Scenario: More than three actionable items
- **WHEN** four or more patterns map to delegation targets
- **THEN** only the three highest-signal items are listed, and the 4th slot is "Other — I'll handle this manually"

#### Scenario: No matching skill for a pattern
- **WHEN** a finding does not map to any delegation target
- **THEN** it is surfaced as plain-text guidance only in the recommended actions list

### Requirement: Inline-only output
Retro SHALL emit the three sections as inline markdown. Retro MUST NOT write any file — no retro file, no `.sessionkit/RETRO.md`, no artifact of any kind.

#### Scenario: Output is inline
- **WHEN** Retro completes synthesis
- **THEN** the three-section markdown appears directly in the conversation; no file is created

### Requirement: User-gated action menu
Retro SHALL present the recommended actions as a multi-select `AskUserQuestion` after the inline summary. Retro MUST NOT invoke any downstream skill before the user answers. A "None — I'm done" option SHALL always be included.

#### Scenario: Action menu presented
- **WHEN** synthesis is complete
- **THEN** Retro calls `AskUserQuestion` with multi-select enabled, one option per recommended action, plus "None — I'm done"

#### Scenario: User selects actions
- **WHEN** the user selects one or more actions
- **THEN** Retro announces the actions to run, then invokes each selected skill sequentially

#### Scenario: User selects none
- **WHEN** the user selects "None — I'm done"
- **THEN** Retro closes with a one-line acknowledgement and invokes no skills

### Requirement: Skill delegation — no absorption
Retro SHALL delegate to skills via the skill tool. Retro MUST NOT absorb or re-implement the logic of any delegated skill. When "encode as a skill" is recommended, Retro delegates to `sessionkit:skillit` — it does not author the skill file itself.

#### Scenario: Skill invoked
- **WHEN** the user selects a skill-backed action
- **THEN** Retro invokes that skill via the skill tool, passing relevant context from the findings as arguments where accepted
