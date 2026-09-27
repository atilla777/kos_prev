# Restore Production Boot

## Goal

Make the supported production Rails configuration boot successfully and ensure
the release test suite detects eager-loading regressions.

## Source Evidence

- `config/environments/production.rb` enables eager loading.
- `config/application.rb` adds `lib` to Rails autoload paths.
- `lib/kos/cli.rb` defines `Kos::CLI`, while the default Zeitwerk inflection for
  `cli.rb` expects `Kos::Cli`.
- `config/initializers/inflections.rb` defines no `CLI` acronym.
- `test/integration/configuration_test.rb` has a positive development boot test
  and only a negative production boot test.
- The full review is retained in `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Resolve the `Kos::CLI` eager-load naming mismatch without changing the public
  `kos` executable or CLI behavior.
- Add a positive isolated production boot test with a configured token and data
  home.
- Ensure the ordinary release check exercises eager loading deterministically,
  rather than only when an ambient `CI` variable happens to be present.
- Update installation or testing documentation only where the verified boot
  contract changes.

## Out Of Scope

- Process supervision, TLS, backup, readiness, or deployment topology.
- Scheduler, workflow, Git, or task lifecycle changes.
- Live model execution.

## Acceptance Criteria

- A production runner and production server can boot with valid isolated
  configuration.
- Eager loading resolves every managed application and library constant.
- A regression equivalent to `Kos::CLI` versus `Kos::Cli` fails an automated
  test run.
- Development and packaged CLI behavior remain unchanged.
- `bin/check` passes.
