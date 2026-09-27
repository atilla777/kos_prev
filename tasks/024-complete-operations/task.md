# Complete Production Operations

## Goal

Provide a reproducible production installation, readiness contract, CI gate,
backup and restore procedure, and revision identity suitable for operating KOS
on its supported single host.

## Source Evidence

- Installation documentation starts the default development Rails server.
- Production assumes an SSL-terminating reverse proxy but documents no matching
  process or proxy setup.
- `/up` proves Rails boot only, not database, migration, catalog, or data-home
  readiness.
- No remote CI workflow runs the authoritative `bin/check` contract.
- Upgrade documentation requests a backup without a SQLite-safe backup/restore
  or rollback runbook.
- CLI version output does not distinguish different source revisions.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Document and test one supported single-host production startup topology,
  including environment, binding, process supervision boundary, and TLS
  termination assumptions.
- Define liveness separately from readiness and make readiness verify the
  persistent state needed to accept task operations.
- Add remote CI that runs the authoritative non-live release check with eager
  loading.
- Document a consistent SQLite backup, integrity check, restore rehearsal, and
  application/database rollback boundary, including relevant worktree handling.
- Expose enough build or revision identity to diagnose mixed server, CLI, and
  OpenCode installations.
- Add an isolated clean production install/start smoke test.

## Out Of Scope

- Multi-host high availability, managed databases, Kubernetes, or automatic
  disaster recovery.
- Live model execution in ordinary CI.
- Per-agent secrets or enterprise observability platforms.

## Acceptance Criteria

- An administrator can follow one documented production procedure from clean
  checkout to a supervised ready service.
- Liveness and readiness have distinct tested meanings; readiness fails when
  required database/catalog state is unavailable.
- Remote CI runs `bin/check` and production eager-load/install smoke coverage.
- Backup and restore instructions produce a consistent database and include a
  verification rehearsal and rollback decision point.
- Installed components expose a common source revision or equivalent provenance
  check.
- Logs retain request correlation and operational failures without exposing the
  bearer token.
- `bin/check` passes.
