# Testing Rules

## Isolation And Layers

- Unit tests cover workflow validation, artifact validation, state transitions,
  canonical repository identity, task graphs, and pure domain behavior.
- Request tests cover exact REST projections, authentication, error codes,
  persistence effects, and transaction rollback.
- Concurrency tests cover selection, ownership and request-creation uniqueness,
  leases, claim fencing, report fencing, dependencies, and graph materialization.
- CLI tests execute the packaged public command and validate exact options,
  standard-input artifact handling, output preservation, and exit statuses.
- Gem tests build and install the CLI into an isolated gem home.
- Skill and profile contract tests verify scheduler boundaries, ID-only dispatch,
  focused operations, permission deny-lists, and step-owned reporting.
- Git tests use temporary source repositories, task worktrees, and bare remotes.
- Migration and recovery tests use isolated persistent SQLite databases, data
  homes, subprocesses, repositories, remotes, and OpenCode configuration homes.
- No test may use the developer's KOS database, data directory, worktree, remote,
  Git configuration, credentials, or ambient database URL.
- Time-sensitive ownership behavior uses controlled time. Tests are deterministic,
  order-independent, and pair failure cases with preserved-invariant assertions.

## Required Properties

The acceptance matrix preserves these exact 23 user-required criteria in order:

1. Agent only ID/context.
2. Context index no bodies.
3. Separate artifact.
4. Atomic artifact+transition.
5. Crash before completion unchanged.
6. Lost response ordinary show.
7. Stale/wrong no write.
8. Bad predecessor backward allowed.
9. Repeated replaces.
10. Answer stored/restart.
11. Scheduler only ID.
12. Scheduler no Markdown/Git.
13. Profile policy.
14. Independent read-only review.
15. Publish->verify.
16. Verify remote independently.
17. Verify failure not complete.
18. Nonpublish no commit/push.
19. Existing IDs/relationships/workflows/worktrees.
20. Clean install assets/workflows.
21. Real development/fix/brief scenarios E2E.
22. No local tasks/id dir.
23. `bin/check`.

The matrix maps each criterion to executable deterministic tests or the exact
`bin/check` contract. Criterion 21 maps the deterministic lifecycle scenarios;
it does not claim model execution. Live development, fix, and brief slash-command
release evidence remains an explicit separate requirement.

## Scenario Coverage

Deterministic development E2E follows `plan`, `implement`, `document`, `review`,
`publish`, and `verify`. It proves required checks occur in implementation, no
built-in `check` step exists, ordinary changes return to implementation, design
failures return to planning, invalid predecessor outcomes route precisely, and
only verification completes. A custom workflow step named `check` remains valid.

Deterministic fix E2E creates and claims by the stable `fix` key, performs
read-only evidenced diagnosis, requires a regression check that would fail for
the reproduced defect, covers `diagnosis_invalid`, and then proves all
development delivery and verification guarantees. Ambiguous behavior or a
non-reproducible report pauses with one question; infrastructure obstruction
pauses as blocked.

Deterministic brief E2E runs briefing in a fresh `kos-brief` agent, verifies OKF
conformance, independently reviews specification and exact graph, validates
before publication, publishes before materialization, and independently verifies
remote specification plus observed graph. One-child and acyclic multi-child
graphs, sibling blockers, parent availability, every backward outcome, repeated
materialization, digest mismatch, and post-publication graph conflict are covered.

State recovery tests restart the server after accepted reports and between
question, answer, resume, and next report. They drop responses before and after
create, report, commit, push, and materialization boundaries and prove recovery
through the appropriate authoritative read. No test creates or consults a local
task artifact directory.
Request-bound creation tests cover lost receipts, changed owners, progressed and
terminal tasks, exact-definition conflicts, concurrent creators, null ordinary
tasks, baseline receipt compatibility, and reversible scoped-key migration.

Repository-identity migration tests preserve numeric IDs, relationships,
workflow snapshots, execution context, and accepted evidence. Malformed or
colliding remotes roll back schema and data. URL and branch tests include
equivalent SSH/HTTPS forms, ambiguous slashes, credentials, ports, unsafe users,
fetch/push mismatch, and Git-invalid branches.

Clean-install tests build the exact CLI gem and install all commands, focused
agents, and skills into an isolated OpenCode configuration. They remove known
obsolete managed agents, compare installed bytes with the checkout, restart the
runtime boundary, and verify command and skill discovery.

Required live release acceptance invokes `/kos-brief`, `/kos`, and `/kos-fix` against an
isolated Rails database, KOS data home, fixture repository, task worktrees, and
bare remote. It proves ID-only scheduling, fresh focused agents, mandatory
checks, read-only authorities, accepted evidence, one publication commit per
task, post-publication verification, completed state, ownership release, and the
brief child graph. The automated suite proves lifecycle and installed-asset
contracts only. Live model execution remains separate release evidence rather
than a credential-dependent ordinary test, and this document does not claim
that evidence has already been produced.

## Commands

- `bin/test` runs the automated suite.
- `bin/lint` performs the non-mutating style check.
- `bin/format` applies automatic formatting fixes.
- `bin/check` prepares the isolated test database, lints, and runs every
  deterministic catalog, API, CLI, migration, lifecycle, skill, Git, recovery,
  installation, and scenario test required for a change.

Every completed change must leave `bin/check` passing.
