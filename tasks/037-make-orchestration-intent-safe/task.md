# Make Orchestration Intent Safe

## Goal

Make `/kos` preserve explicit user intent about planning, workflow selection,
and execution instead of silently substituting workflows or starting workers
before authorization.

## Scope

- Define planning-only requests as atomic task-plan storage followed by a stop
  before any ready-task query, claim, takeover, or worker dispatch.
- Define workflow selection for ordinary implementation, defect correction,
  specification work, and explicitly requested custom workflows.
- Require an explicit question when a requested workflow is absent rather than
  guessing keys or creating a reduced global workflow as a fallback.
- Clarify that the supported command is `/kos`; retired `/kos-brief` semantics
  must not be reintroduced implicitly.
- Resolve the built-in `brief` contract so its workers do not propose a task plan
  that no actor is authorized to materialize.
- State that cancelling a worker does not mutate KOS and requires authoritative
  rereading before takeover or later release.

## Out Of Scope

- Restoring workflow-specific slash commands or schedulers.
- Having the orchestrator perform, judge, or report a worker step.
- Automatic cancellation propagation, leases, heartbeat, or retry.
- Claim release, which is handled by task 039.

## Acceptance Criteria

- An explicit planning-only goal stores or updates an unstarted plan and leaves
  every task pending without creating a claim.
- An execution goal uses a discoverable existing workflow and never creates a
  fallback workflow merely because a key lookup failed.
- An absent explicitly requested workflow produces one material question and no
  coordination mutation.
- The brief workflow has one unambiguous specification/review/publication
  responsibility and a new immutable catalog revision if its definition changes.
- Orchestrator guidance explains known worker cancellation and observation
  without claiming that OpenCode cancellation changes KOS state.
- Specifications, skills, built-in tests, and agent-contract tests agree, and
  `bin/check` passes.
