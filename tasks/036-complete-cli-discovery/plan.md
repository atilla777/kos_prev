# Plan

1. Inventory command signatures, response projections, schema validation, and
   generic not-found paths against the installed CLI contract.
2. Define one authoritative workflow schema representation shared by validation,
   `workflow schema`, and generated help or examples without duplicating policy.
3. Add thin `workflow list`, `workflow show`, and `workflow schema` commands and
   enrich common command help and task workflow projections.
4. Add resource-specific additive not-found diagnostics, especially for unknown
   workflow keys during atomic plan storage.
5. Update specifications, architecture, README, and `kos-cli` guidance; remove
   the stale statement that the agent-led MVP is still planned.
6. Add focused API, CLI, schema, error, and skill tests; run `bin/check`, obtain
   independent review, address findings, and publish the completed task.
