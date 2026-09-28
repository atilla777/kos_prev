# Status

State: planned
Updated: 2026-09-28

## Current

Claims are deliberately non-expiring. A stopped worker can be replaced through
takeover or its whole plan can be abandoned, but one known cancelled dispatch
cannot be returned to pending without immediately assigning a new claim.

## Decisions

- Add only an explicit fully fenced release; do not add leases or time-based
  policy.
- Require the original immutable worker envelope so a caller cannot release
  newly taken-over work accidentally.
- Keep external-effect assessment with the orchestrator before release.

## Next

Begin after orchestration intent and repository recovery behavior are stable.

## Blockers

- Depends on tasks 037 and 038.
