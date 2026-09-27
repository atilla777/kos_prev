# Status

State: done
Updated: 2026-09-27

## Current

Custom task types are executable through `/kos-task <task-type-key>` for existing
tasks. The command uses a fixed advanced agent for `main`; `model_tier` selects
only a `subagent` profile. Built-in keys remain exclusive to their commands.

Workflow validation requires every reachable step to have a completion path,
and task creation revalidates persisted workflow revisions. The deterministic
custom scenario covers exact selection, both modes, backward execution,
pause/resume, and completion.

## Next

Task 022 may proceed.

## Blockers

None.

## Checks

- `bin/check`
- 273 tests, 4005 assertions, 0 failures, 0 errors, 0 skips.
- Independent review completed; all findings were addressed.
