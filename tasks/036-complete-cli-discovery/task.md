# Complete CLI Discovery

## Goal

Make the installed CLI sufficient to discover reusable workflows, construct
valid definitions, and invoke ordinary operations without source inspection or
repeated speculative calls.

## Scope

- Expose the existing workflow revision list and read API through `workflow
  list` and `workflow show`.
- Add `workflow schema` as a read-only representation of the authoritative
  workflow definition contract, including one valid example.
- Make per-command help identify required arguments, accepted identifiers,
  input shapes, response fields, and concise examples for the common project,
  workflow, plan, and task lifecycle operations.
- Keep `kos-cli` concise while including ready-to-use signatures for the common
  orchestration and recovery path; reserve help discovery for uncommon details.
- Preserve stable error discriminators while making absent workflow, plan,
  task, and result diagnostics identify the missing resource and lookup value.
- Return useful workflow identity in task discovery without requiring a second
  undocumented lookup.
- Keep workflow revisions immutable and avoid a separate persisted schema or
  workflow status lifecycle.

## Out Of Scope

- Repository checkout discovery, aggregate project status, or scheduling.
- Claim release, leases, heartbeat, or automatic stale-worker detection.
- A web UI or compatibility aliases for retired commands.

## Acceptance Criteria

- A clean administrator can list workflow keys and revisions, inspect one
  revision, print the workflow schema, and create a valid custom workflow using
  only installed CLI help and output.
- `workflow create --help` states the exact root, step, outcome, and transition
  shapes and contains a valid complete example.
- Common command help makes positional versus option identifiers and required
  values unambiguous.
- An unknown workflow selected by `plan put` reports its key while retaining a
  stable machine-readable error discriminator and changing no state.
- Task discovery exposes the selected workflow ID, key, and revision.
- Product, architecture, CLI skill, README, API, and CLI tests cover the public
  surface, and `bin/check` passes.
