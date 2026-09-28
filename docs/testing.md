# Testing Rules

Tests prove focused production contracts, not prose algorithms or simulated
agent intelligence.

## Coverage

- Workflow tests cover immutable revisions, structural validation, generic
  outcomes, backward transitions, pauses, and completion without name-based
  built-in behavior.
- Plan tests cover atomic creation and replacement, replacement rejection after
  work starts, missing references, dependency cycles, and readiness only after
  every blocker completes.
- Lifecycle tests cover non-expiring claims, optimistic versions, conflicting
  claims, explicit takeover, stale claim/version/step rejection, one worker per
  task, and parallel claims for independent tasks.
- Result tests cover atomic result-plus-transition acceptance, replacement of a
  repeated step's latest result, no partial write on failure, and focused result
  retrieval.
- Pause tests cover durable question or obstruction storage, claim release,
  exact answer binding, readiness for a new claim, clearing after an accepted
  report, and process restart.
- Request tests cover authentication, project-scoped unfinished-state
  discovery, API projections, stable validation and conflict errors,
  transaction rollback, and persistence.
- CLI tests execute the packaged client and cover discoverable help, health,
  claim identity generation, argument and standard-input mapping, output
  preservation, and exit statuses for every public command family.
- Installation tests verify exactly one `/kos` command, one `kos-worker` agent,
  and skills `kos`, `kos-cli`, `kos-worker`, and `okf`.
- Agent-contract tests verify orchestrator-only coordination, one worker per
  step, worker-owned reporting, and concurrent dispatch of independent tasks
  without implementing a second scheduler in the test suite.
- Persistence tests use isolated SQLite databases and restart the application
  across claims, accepted reports, pauses, answers, and fresh-session discovery.

Tests must not use a developer's database, credentials, OpenCode configuration,
or repository state. Concurrency tests assert both the winning write and the
unchanged invariant after rejected writes. No test depends on wall-clock claim
expiry because claims do not expire.

## Exclusions

Ordinary acceptance does not require live-model execution, deterministic Git or
publication scenarios, semantic review evaluation, required-check assertions,
brief graph materialization, request-bound command framing, task-type routing,
main-step execution, leases, or scheduler prose-literal tests.

Workers may choose such tools and procedures when workflow instructions permit
them, but KOS tests only its storage and coordination boundary. Passing tests do
not claim that worker-authored evidence is semantically correct.

## Commands

- `bin/test` runs the automated suite.
- `bin/lint` runs non-mutating style checks.
- `bin/format` applies automatic formatting.
- `bin/check` prepares isolated test state, verifies eager loading, lints, and
  runs the complete production contract suite.

Every completed change must leave `bin/check` passing. Remote CI uses the same
contract; no separate live-model release gate is required.
