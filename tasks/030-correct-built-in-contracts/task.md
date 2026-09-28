# Correct Built-In Workflow Contracts

## Goal

Keep built-in workflows immutable and upgradeable while preserving the same
generic lifecycle and role boundaries used by custom workflows.

## Scope

- Introduce an explicit built-in catalog revision strategy that creates new
  immutable revisions when definitions change.
- Keep existing tasks pinned to their original workflow revisions.
- Make readiness validate the installed canonical catalog without requiring an
  obsolete revision to equal current source definitions.
- Remove plan storage from the `brief` publish worker instruction; plan
  maintenance remains orchestrator-owned.
- Add focused tests for catalog upgrade and built-in instruction boundaries.

## Out Of Scope

- Special server semantics for development, fix, brief, review, or publication.
- Migration of PLAN-022 data.
- Semantic validation of worker results.

## Acceptance Criteria

- Seeding a changed built-in definition creates a new immutable revision and is
  idempotent afterward.
- Existing tasks continue using their selected revision after an upgrade.
- Readiness succeeds when the current built-in catalog revision is installed.
- No built-in worker instruction asks a worker to create, replace, claim, answer,
  schedule, or take over KOS work.
- Custom and built-in workflows still execute through identical transitions.
- `bin/check` passes.
