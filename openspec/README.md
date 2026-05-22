# OpenSpec

Behavioral specifications for capabilities in this repository.

## Layout

```
openspec/
  specs/
    <capability>/
      spec.md         # The OpenSpec specification (machine-validated)
      REFERENCES.md   # Source citations backing every requirement and scenario
  inventory/
    modules/
      <name>.md       # Optional module inventory briefs (maps, not specs)
```

## Validate a spec

```bash
bash scripts/openspec validate <capability> --type spec --strict
```

## Authoring

**Baselining existing capabilities** — use `/spec-baseline` to reverse-engineer a spec
from code that already exists. The output includes a `REFERENCES.md` that cites every
requirement back to specific file:line evidence.

**Proposing changes** — once a capability is baselined, use `/opsx:propose` to draft
changes against the existing spec rather than modifying it directly. Proposed changes
go through a review and apply workflow before the spec is updated.
