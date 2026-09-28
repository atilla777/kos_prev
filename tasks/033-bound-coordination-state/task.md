# Bound Coordination State

## Goal

Prevent accidental resource exhaustion from oversized plans, workflows, pause
state, and accumulated results while keeping limits simple for a trusted
single-installation deployment.

## Scope

- Define documented limits for plan task and dependency counts, workflow steps
  and outcomes, text inputs, and total accepted-result state.
- Replace recursive dependency traversal with a bounded iterative validation.
- Reject oversized definitions and lifecycle inputs before partial writes.
- Preserve the existing 1 MiB individual result limit or replace it with one
  clearly documented consistent policy.
- Cover boundary values and unchanged state after rejection.

## Out Of Scope

- Multi-tenant quotas, billing, rate limiting, or distributed admission control.
- External artifact storage or full attempt history.
- Premature database normalization without measured need.

## Acceptance Criteria

- Every untrusted variable-size API input has a documented finite bound.
- A deeply nested but otherwise valid dependency chain cannot exhaust the Ruby
  stack.
- Oversized plans, workflows, results, pauses, and answers fail with stable
  errors and no partial state changes.
- Normal built-in and custom workflows remain concise and unaffected.
- Boundary, rollback, and persistence tests pass.
- `bin/check` passes.
