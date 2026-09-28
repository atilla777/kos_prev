# Status

State: done
Updated: 2026-09-28

## Current

`task release` now returns one exact active dispatch to pending at the same
workflow step, clears its claim, and advances task and plan versions. The API,
packaged CLI, orchestrator guidance, specifications, and installation guidance
distinguish release from takeover, pause, and plan abandonment.

## Decisions

- Add only an explicit fully fenced release; do not add leases or time-based
  policy.
- Require the original immutable worker envelope so a caller cannot release
  newly taken-over work accidentally.
- Keep external-effect assessment with the orchestrator before release.
- Reuse existing pending state rather than adding a release status or schema.

## Verification

- `bin/check` passes: 119 tests, 1878 assertions, no failures or errors.
- Packaged CLI coverage proves release survives SQLite backup and restore as
  ready pending work at the same step.
- Independent review found no production correctness or safety defects. Its one
  low-severity test gap for explicit `blocked` rejection was added before the
  final check.

## Blockers

- None.
