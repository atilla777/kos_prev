# Status

State: planned
Updated: 2026-09-28

## Current

The orchestrator currently stores a plan and coordinates execution without an
explicit planning-only stop rule. Workflow selection is unspecified, and the
brief workflow asks for a proposed task plan even though brief workers and
publishers do not own KOS plan maintenance. Runtime worker cancellation leaves
the authoritative claim unchanged by design.

## Decisions

- Explicit planning-only language authorizes plan storage, not execution.
- Unknown workflows are discovered or questioned, never guessed or replaced by
  an ad hoc reduced workflow.
- Keep one generic `/kos` command and narrow `brief` rather than reviving
  `/kos-brief`.

## Next

Begin after task 036 provides workflow discovery through the public CLI.

## Blockers

- Depends on task 036.
