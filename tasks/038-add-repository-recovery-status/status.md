# Status

State: done
Updated: 2026-09-28

## Current

`project resolve --remote REMOTE` now reads and normalizes one explicitly
selected checkout remote before exact registration lookup. `status --remote
REMOTE` returns the project and its default non-completed plans and tasks in one
authenticated read without lifecycle mutation or worker-liveness inference.

## Decisions

- Permit read-only inspection of one explicitly selected local Git remote as a
  narrow CLI exception.
- Keep registration explicit and all recovery classification agent-owned.
- Do not infer staleness or mutate lifecycle state from `status`.
- Keep one aggregate read endpoint so a CLI command preserves one-request output
  semantics and observes one transactional server snapshot.

## Checks

- Focused CLI, API, skill, and installed-gem tests pass.
- `bin/check`: 113 tests, 1763 assertions, passing.
- Independent review completed with no findings; unusual corrupt Git
  configuration remains a diagnostic-only residual risk.

## Next

Task 039 is the next dependency-ready roadmap item.

## Blockers

- None.
