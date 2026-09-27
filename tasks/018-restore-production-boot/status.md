# Status

State: done
Updated: 2026-09-27

## Current

Production eager loading first failed expecting `Kos::Cli` from
`lib/kos/cli.rb`, then exposed the equivalent existing `Kos::Version` mismatch
for `Kos::VERSION`. Both public constants now have matching inflections. The
positive isolated production boot test covers eager loading, the CLI constant,
and database configuration, while `bin/check` runs `zeitwerk:check` explicitly.

## Next

Task 019 is now the first planned task with completed dependencies.

## Blockers

None.

## Checks

- Before fix: isolated production runner failed with `Zeitwerk::NameError` for
  `Kos::Cli`; after that correction it exposed the same error for `Kos::Version`.
- The valid production boot fixture supplies Rails' required `SECRET_KEY_BASE`
  in addition to the KOS token and isolated data home.
- `bin/rails test test/integration/configuration_test.rb test/integration/plan_022_acceptance_matrix_test.rb`
  passed: 16 runs, 150 assertions.
- `RAILS_ENV=test bin/rails zeitwerk:check` passed.
- Isolated production `bin/rails server` smoke test returned HTTP 200 from
  `/up`.
- `bin/check` passed: 249 runs, 3801 assertions, 0 failures, 0 errors.
