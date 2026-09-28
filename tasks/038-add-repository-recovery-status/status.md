# Status

State: planned
Updated: 2026-09-28

## Current

Recovery requires the caller to derive a canonical identity from Git, call
`project show`, then separately list plans and tasks. The server already returns
the necessary authoritative state, but the installed CLI offers no focused
current-checkout resolution or aggregate recovery view.

## Decisions

- Permit read-only inspection of one explicitly selected local Git remote as a
  narrow CLI exception.
- Keep registration explicit and all recovery classification agent-owned.
- Do not infer staleness or mutate lifecycle state from `status`.

## Next

Begin after task 036 establishes complete workflow and response discovery.

## Blockers

- Depends on task 036.
