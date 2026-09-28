# Status

State: done
Updated: 2026-09-28

## Current

Built-in definitions now use an explicit catalog revision. Idempotent seeding
creates immutable revisions for changed definitions, rejects conflicting current
entries atomically, and leaves existing tasks pinned to obsolete revisions.
Readiness validates only the complete current catalog, and the brief publisher
no longer performs orchestrator-owned plan storage.

## Next

Task 031 can prove installed orchestration against the corrected contracts.

## Blockers

None.

## Checks

- `bin/check` passed: 83 tests, 1120 assertions, 0 failures.
- Independent review found no remaining correctness, regression, test, or
  documentation findings after catalog-conflict and canonical-name validation
  findings were resolved.
