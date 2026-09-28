# Testing Rules

Tests prove focused production contracts, not prose algorithms or simulated
agent intelligence.

## Coverage

- Workflow tests cover immutable revisions, structural validation, generic
  outcomes, backward transitions, pauses, and completion without name-based
  built-in behavior. They also prove that the published schema and example agree
  with validation.
- Plan tests cover atomic creation, replacement and abandonment, replacement
  rejection after work starts, dependency cycles, and dependency blocking.
- Lifecycle tests cover non-expiring claims, optimistic versions, conflicting
  claims, explicit takeover, stale claim/version/step rejection, one worker per
  task, terminal abandoned work, and parallel claims for independent tasks.
- Result tests cover atomic result-plus-transition acceptance, replacement of a
  repeated step's latest result, no partial write on failure, and focused result
  retrieval.
- Pause tests cover durable question or obstruction storage, claim release,
  exact answer binding, and readiness for a new claim.
- Request tests cover authentication, project-scoped non-completed-state
  discovery, API projections, status mapping and selected stable error bodies,
  resource-specific not-found diagnostics, task workflow identity, transaction
  rollback, bounded request and definition inputs, and persistence.
- CLI tests execute the packaged client and cover discoverable help, health,
  installation identity/readiness checks, claim identity generation, argument
  and standard-input mapping, workflow list/show/schema, complete command shape
  and response help, output preservation, and exit statuses for every public
  command family.
- Installation tests verify exactly one `/kos` command, one `kos-worker` agent,
  skills `kos`, `kos-cli`, `kos-worker`, and `okf`; clean and legacy installation,
  manifest-owned stale cleanup, unmanaged-file preservation, compatibility
  failure, and abandonment persistence across backup and restart.
- Agent-contract tests verify the installed inventory, frontmatter, immutable
  worker envelope, and durable role boundaries without treating exact prose as
  executable behavior.
- Persistence tests use isolated SQLite databases and exercise backup and
  restore of completed and abandoned lifecycle inspection state plus
  fresh-session discovery.
- Limit tests cover collection, request-body, result, aggregate-result, and
  representative text boundaries, iterative maximum-depth dependency
  validation, and unchanged state after rejected writes.

Tests must not use a developer's database, credentials, OpenCode configuration,
or repository state. Concurrency tests assert both the winning write and the
unchanged invariant after rejected writes, including abandonment races with
claim, report, answer, and takeover. No test depends on wall-clock claim expiry
because claims do not expire.

## Exclusions

Ordinary acceptance does not require live-model execution, deterministic Git or
publication scenarios, semantic review evaluation, required-check assertions,
brief graph materialization, request-bound command framing, task-type routing,
main-step execution, leases, or scheduler prose-literal tests.

Workers may choose such tools and procedures when workflow instructions permit
them, but KOS tests only its storage and coordination boundary. Passing tests do
not claim that worker-authored evidence is semantically correct.

The retained task 031 clean-install acceptance record separately demonstrates a
real installed `/kos` run with parallel worker dispatch, pause and answer,
fresh-session discovery, takeover, and completion. Its verifier checks the
recorded evidence; it is not a new live-model run for each release.

## Commands

- `bin/test` runs the automated suite.
- `bin/lint` runs non-mutating style checks.
- `bin/format` applies automatic formatting.
- `bin/check` prepares isolated test state, verifies eager loading, lints, and
  runs the complete production contract suite.

Every completed change must leave `bin/check` passing. Remote CI uses the same
contract; no separate live-model release gate is required.
