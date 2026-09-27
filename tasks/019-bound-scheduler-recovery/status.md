# Status

State: done
Updated: 2026-09-27

## Current

The scheduler now compares status, current step, claim version, and accepted
current-step evidence before and after every execution. Unchanged valid claims
stop explicitly; an expired claim permits one exact fenced resume and one retry
without retaining local protocol state. A controllable harness executes main and
ID-only subagent paths against fake CLI state.

## Next

Task 020 is now the first planned task with completed dependencies.

## Blockers

None.

## Checks

- Scheduler recovery tests passed: 9 runs, 57 assertions.
- Scheduler and skill tests passed together: 21 runs, 376 assertions.
- Independent read-only review findings on exact resume confirmation and retry
  coverage were fixed; wrong owner, step, fence, and lease observations now stop
  before dispatch.
- `bin/lint` passed: 86 files, no offenses.
- `git diff --check` passed.
- `bin/check` passed: 258 runs, 3866 assertions, 0 failures, 0 errors,
  0 skips.
