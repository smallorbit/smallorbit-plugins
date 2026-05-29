# OpenSpec

Behavioral specifications for capabilities in this repository.

## Layout

```
openspec/
  specs/
    <capability>/
      spec.md         # The OpenSpec specification (machine-validated)
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
from code that already exists.

**Proposing changes** — once a capability is baselined, use `/opsx:propose` to draft
changes against the existing spec rather than modifying it directly. Proposed changes
go through a review and apply workflow before the spec is updated.

**Implementing changes** — stock `/opsx:apply` walks a change's `tasks.md` linearly in
one conversation. For changes that span multiple capabilities or have parallelizable
work, the **opsx-bridge** plugin offers a multi-agent alternative: once a change is
proposed and ready, `/opsx-bridge:apply-via-squad <change>` dispatches it to a
coordinated crew (one architect over cross-capability work) and
`/opsx-bridge:apply-via-swarm <change>` dispatches it to a parallel swarm (one agent
per `tasks.md` section). See [`plugins/opsx-bridge/README.md`](../plugins/opsx-bridge/README.md)
for the dispatcher decision table.
