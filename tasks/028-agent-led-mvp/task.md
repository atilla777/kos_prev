# Simplify KOS To An Agent-Led MVP

## Goal

Reshape KOS into a small authoritative store for task plans, generic workflow
definitions, and task state. Keep only the deterministic coordination needed by
multiple capable agents, while moving diagnosis, implementation, review, test
selection, Git work, publication, and recovery judgment out of the orchestrator
and application business logic.

## Product Decisions

- The main agent is an orchestrator: it plans, selects ready work, claims tasks,
  dispatches workers, presents pauses, performs explicit takeover, and observes
  state. It does not execute substantive workflow steps.
- Worker agents perform exactly one workflow step and own all semantic and
  repository decisions allowed by that step.
- Independent tasks may execute in parallel. One task has one current step and
  one active worker.
- Concurrency uses an atomic claim plus optimistic task version. Claims do not
  expire; recovery is an explicit version-fenced takeover. The MVP has no
  leases, heartbeat, clock comparison, or automatic redispatch.
- The server validates storage, dependencies, claims, versions, and generic
  workflow transitions. It does not validate the semantic truth of checks,
  review, Git, or publication evidence.
- Built-in workflows are defaults over the same generic mechanism as custom
  workflows. They confer no server-side special behavior.
- Skills teach capabilities, commands, role boundaries, and essential
  invariants. They must not reproduce deterministic application, Git, shell,
  retry, or review algorithms in prose.

## Scope

- Define the smallest durable project, workflow, task-plan, dependency, claim,
  pause, answer, and accepted-result contracts required by `specs/kos.md`.
- Replace owner, lease, and claim-version recovery with one simple non-expiring
  claim identity plus optimistic task version and explicit takeover.
- Provide an atomic operation for creating or replacing a not-yet-started task
  plan with dependencies.
- Remove built-in-only required-check, publication, brief-graph, graph-digest,
  and task-type completion rules from the server lifecycle.
- Reduce built-in workflow instructions to concise worker objectives,
  authorities, observable results, and allowed outcomes.
- Ensure the orchestrator dispatches every substantive step to a worker and can
  dispatch independent claimed tasks concurrently.
- Simplify CLI operations and KOS skills around context, ready work, claim,
  takeover, report, pause, answer, and plan storage.
- Replace prose-literal tests and parallel test-only scheduler algorithms with
  tests of the production state and command contracts.
- Reconcile `docs/specification.md`, `docs/architecture.md`, `docs/testing.md`,
  installation guidance, README, and managed OpenCode assets with the reduced
  product contract.
- Remove obsolete state and compatibility behavior rather than retaining dual
  paths; use a focused migration or documented pre-release reset as appropriate.

## Out Of Scope

- Implementing an agent runtime or server-started workers.
- Deterministic Git publication, check execution, semantic review validation,
  model evaluation, or repository sandboxing.
- Multi-tenant credentials, per-agent authorization, untrusted repository
  isolation, high availability, or multi-host execution.
- Leases, heartbeat, automatic stale-worker detection, automatic retry, or
  parallel execution of multiple steps within one task.
- A web UI, full attempt history, or release attestation based on mandatory live
  model runs.
- Preserving PLAN-022 complexity solely for compatibility with unshipped
  pre-release behavior.

## Acceptance Criteria

- The implementation matches the agent-led product boundaries in
  `specs/kos.md` without retaining contradictory special-case guarantees.
- A plan containing tasks and dependencies is stored atomically and exposes
  only dependency-ready tasks for claiming.
- Separate orchestrator dispatches can claim and execute independent tasks in
  parallel, while conflicting claims or stale reports for one task are rejected.
- Explicit takeover invalidates the prior worker without time, lease, or
  heartbeat logic.
- The orchestrator never performs diagnosis, implementation, review, test
  selection, Git work, or publication; a worker reports exactly one step.
- Built-in and custom workflows use the same generic transition and completion
  rules.
- Skills contain concise capability and safety guidance rather than complete
  deterministic algorithms.
- Focused tests cover plan atomicity, dependencies, parallel claims, takeover,
  stale reports, generic transitions, pause/answer persistence, and restart.
- `bin/check` passes and current documentation describes only guarantees the
  simplified implementation actually provides.
