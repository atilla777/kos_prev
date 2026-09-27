# Harden Brief Graphs

## Goal

Prevent materialized brief graphs from becoming irrecoverable, stranding child
tasks, or exhausting the SQLite service with unbounded graph input.

## Source Evidence

- `BriefTaskGraph#materialize!` rejects all later materialization once children
  exist.
- Publication rewinds are rejected after children exist.
- Cancelling a materialized brief is still allowed and leaves every child
  blocked on a parent that can never complete.
- Graph identity is not mechanically bound to structured accepted review
  evidence.
- Child count, field sizes, edge count, and recursion depth are unbounded.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Define one authoritative graph identity that publication approval,
  materialization, observation, and completion can compare mechanically.
- Provide a safe pre-completion recovery path for an accidentally wrong but
  otherwise valid materialization without exposing partial children.
- Define cancellation semantics that cannot leave permanently blocked children.
- Add explicit child, edge, depth, key, title, and description limits appropriate
  for a single SQLite transaction.
- Replace recursion where necessary to make validation safe at the accepted
  limits.
- Preserve atomic all-or-nothing graph creation and request recovery by
  authoritative observation.

## Out Of Scope

- General arbitrary graph versioning or deletion of unrelated tasks.
- Parallel task execution inside one workflow.
- Moving Git state or graph proposals into a universal task-state document.

## Acceptance Criteria

- A materialized graph cannot differ silently from the approved graph identity.
- An interrupted exact retry is distinguishable from a conflicting graph.
- A valid but wrong pre-completion graph has a documented safe resolution.
- Cancelling or otherwise terminating a materialized brief cannot strand active
  or pending children permanently.
- Oversized, too-deep, or too-dense graphs fail before persistence with no
  partial rows and no stack overflow.
- Concurrent materialization, report, recovery, and cancellation tests preserve
  every invariant.
- `bin/check` passes.
