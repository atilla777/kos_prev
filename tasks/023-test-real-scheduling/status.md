# Status

State: done
Updated: 2026-09-27

## Current

The installed-command harness now executes development, fix, brief, and custom
scheduler control flow around the real lifecycle domain. It verifies installed
commands, skills, and profiles; ID-only tier dispatch; fixed custom-main model
selection; ownership; backward transitions; pause/resume; and terminal progress.
Task-019 recovery tests retain executed crash, unchanged, lease-expiry, and
bounded retry coverage.

## Next

Proceed to task 024, completing production operations.

## Blockers

None.

## Checks

- `bin/check` passed on 2026-09-27: 278 tests, 4191 assertions, 0 failures,
  0 errors, 0 skips.
