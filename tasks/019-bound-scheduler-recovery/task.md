# Bound Scheduler Recovery

## Goal

Ensure one scheduler invocation either observes authoritative progress, performs
one safe recovery action, or stops explicitly instead of redispatching an
unchanged step indefinitely.

## Source Evidence

- `skills/kos/SKILL.md` unconditionally repeats dispatch after rereading context.
- A child crash or rejected report leaves the task active at the same step.
- An expired lease makes every report stale until a fenced resume renews it.
- Server-side report and resume fencing is already implemented in
  `TaskLifecycle`; the missing invariant is bounded scheduler behavior.
- See task 018's `artifacts/readiness-review-2026-09-26.md`.

## Scope

- Define progress as an authoritative change in status, current step, claim
  version, or accepted current-step evidence.
- Compare pre-execution and post-execution context for each dispatched step.
- Stop explicitly after an unchanged failed execution while its lease remains
  valid; never launch another executor blindly.
- Recover an expired claim through the existing exact fenced resume path before
  at most one subsequent dispatch.
- Preserve ID-only subagent prompts and the rule that child prose is not an
  authoritative result.
- Cover child crash, rejected report, expired lease, successful transition,
  pause, cancellation, and completion.

## Out Of Scope

- Heartbeats, attempt tables, report receipts, or durable scheduler-local state.
- Changing lease duration or weakening stale-owner fencing.
- Git-specific recovery or publication logic.

## Acceptance Criteria

- One unchanged child return cannot cause an unbounded dispatch loop.
- An expired active claim is resumed with the exact observed fence before work
  is retried.
- A valid transition continues to the next authoritative step.
- A pause or terminal state stops without another dispatch.
- Recovery retains no durable local protocol file or artifact bytes.
- Behavioral tests execute the loop against a controllable fake CLI and child
  runner rather than only searching scheduler Markdown.
- `bin/check` passes.
