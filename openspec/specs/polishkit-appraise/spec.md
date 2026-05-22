# Appraise

## Purpose
Appraise produces a scored, read-only quality assessment of code across five weighted dimensions — architecture, naming, algorithmic elegance, testability, and idiomatic consistency — with beauty highlights and violation flags. It is a connoisseur-style evaluation tool that leads with genuine craft observations before surfacing improvement opportunities.

## Requirements

### Requirement: Scope survey
Appraise SHALL determine the target scope from user input and read enough representative code to support scoring. For a single file or pasted snippet, it reads that content directly. For a directory or module, it surveys the structure and reads key files. For a full repository, it surveys the project structure, identifies architectural boundaries, and samples representative files across layers. Appraise SHALL NOT attempt to read every file in a large scope; representative sampling is sufficient.

#### Scenario: Single file scope
- **WHEN** a single file path or code snippet is provided
- **THEN** Appraise reads that content directly and bases its assessment on it

#### Scenario: Repository or module scope
- **WHEN** a directory, module path, or no scope is provided
- **THEN** Appraise surveys the directory tree, identifies entry points and architectural layers, and reads a representative cross-section before scoring

### Requirement: Language detection and idiomatic lens
Appraise SHALL detect the primary language(s) present in the scope. For each detected language, Appraise SHALL apply that language's idiomatic standards when scoring the Idiomatic Consistency dimension alongside universal principles. Where a language has an associated application framework in widespread use, Appraise SHALL additionally apply that framework's conventions.

#### Scenario: Language detected
- **WHEN** a primary language is identifiable in the scope
- **THEN** Appraise applies that language's idiomatic standards for the Idiomatic Consistency dimension

### Requirement: Five-dimension scoring
Appraise SHALL score the code across exactly five dimensions. Each dimension MUST be scored on a 1–10 scale. The overall score SHALL be the weighted sum: Architecture & Separation of Concerns (30%), Naming & Readability (25%), Algorithmic Elegance (20%), Testability & Test Design (15%), Idiomatic Consistency (10%), rounded to one decimal place.

#### Scenario: Overall score computed
- **WHEN** all five dimension scores are assigned
- **THEN** overall score = (Architecture × 0.30) + (Naming × 0.25) + (Algorithmic Elegance × 0.20) + (Testability × 0.15) + (Idiomatic Consistency × 0.10), rounded to one decimal place

#### Scenario: Verdict tier assigned
- **WHEN** the overall score is computed
- **THEN** a verdict tier is assigned: 9.0–10.0 Masterwork, 7.5–8.9 Polished, 6.0–7.4 Competent, 4.0–5.9 Rough, 1.0–3.9 Needs Rethinking

### Requirement: Always-flag violations
Regardless of dimension scores, Appraise SHALL flag any of the following when found: god classes or god objects; magic numbers or magic strings; comments that restate what the code does; functions exceeding approximately 30 lines; files exceeding approximately 300 lines. These SHALL appear in a dedicated Violations section.

#### Scenario: God class present
- **WHEN** a class, module, or file carries multiple unrelated responsibilities beyond a single clear purpose
- **THEN** it is flagged in the Violations section with a file reference

#### Scenario: Oversized function present
- **WHEN** a function body exceeds approximately 30 lines
- **THEN** it is flagged in the Violations section with a file:line reference

#### Scenario: No violations found
- **WHEN** none of the always-flag conditions are present
- **THEN** the Violations section states that no violations were found

### Requirement: Report structure and length
Appraise SHALL produce its output in this section order: Executive Summary, Beauty Highlights, Dimension Breakdown, Violations, Closing Note. The report MUST stay under 500 lines total. The Executive Summary MUST include the overall score, verdict tier, a one-sentence characterization of the codebase, the single most beautiful thing observed, and the single most impactful improvement opportunity. The Beauty Highlights section MUST call out 2–5 specific instances of genuinely elegant code with the principle at work named.

#### Scenario: Sections appear in prescribed order
- **WHEN** Appraise produces its report
- **THEN** sections appear in the order: Executive Summary → Beauty Highlights → Dimension Breakdown → Violations → Closing Note

#### Scenario: Report stays under length limit
- **WHEN** Appraise produces its report
- **THEN** the total output is under 500 lines

### Requirement: Read-only operation
Appraise SHALL NOT modify, create, or delete any files. It SHALL NOT create branches or open pull requests. Its only output is the scored report delivered in the current conversation.

#### Scenario: Assessment completes
- **WHEN** Appraise finishes its assessment
- **THEN** no files have been created, modified, or deleted and no branches or PRs exist as a result of the invocation
