---
type: Product Specification
title: KOS task coordination
description: Durable task plans, generic workflows, and authoritative state for cooperating AI agents.
tags:
  - kos
  - workflows
---

# Goal

KOS is a small authoritative store for task plans, workflow definitions, and
the current state of each task. It gives capable AI agents enough shared state
and concurrency control to coordinate work without encoding their reasoning or
repository procedures in the application.

KOS coordinates agents; it does not perform or judge their substantive work.

# Actors

- A user gives the main orchestrator a goal and answers material questions.
- A main orchestrator creates or updates a task plan, claims ready tasks, starts
  workers, and observes authoritative state. It does not diagnose, implement,
  review, test, or publish task work itself.
- A worker agent performs exactly one current workflow step. Depending on the
  step, it may diagnose, plan, implement, select and run checks, review, use
  Git, or publish.
- An administrator registers projects and may define reusable workflows.

# User Scenarios

- The main orchestrator turns a goal into an ordered or dependency-linked plan
  of tasks and stores that plan in KOS.
- The main orchestrator finds ready tasks, claims independent tasks atomically,
  and runs multiple worker agents in parallel on different tasks.
- A worker reads its task, current workflow step, and relevant prior results;
  performs the step using its own reasoning and tools; and reports one allowed
  outcome with useful evidence.
- A reported outcome advances, pauses, or completes the task according to its
  stored workflow definition.
- A worker can pause with one question or a concrete obstruction. The answer or
  resolution is stored with the task before the same step continues.
- After a worker or orchestrator interruption, a later orchestrator discovers
  the project's unfinished plans and tasks, reads their KOS state, and
  explicitly takes over unfinished work when appropriate.
- Built-in development, fix, and brief workflows may be supplied as convenient
  defaults, while custom workflows use the same generic state semantics.

# Rules

- KOS stores projects, immutable workflow revisions, tasks, task dependencies,
  current workflow position, claims, versions, pauses, answers, and the latest
  accepted result for each executed step.
- A task remains bound to the workflow revision selected when it is created.
- A workflow declares steps, concise instructions, allowed outcomes, and the
  transition associated with each outcome. KOS validates workflow shape and
  transitions but does not interpret instruction or result meaning.
- Built-in and custom workflows use the same transition mechanism. A step or
  task-type name gives the server no special Git, check, review, publication,
  graph, or completion semantics.
- The main orchestrator owns scheduling only: plan maintenance, ready-task
  selection, claiming, worker dispatch, pause presentation, takeover, and state
  observation. It never substitutes its own work for a worker step.
- A worker owns one substantive step. Its stored workflow instruction defines
  the objective and authority; the worker chooses the appropriate reasoning,
  repository tools, checks, Git operations, and evidence.
- A worker reports its own result and never executes the next step.
- Independent ready tasks may run concurrently. One task has at most one active
  claim and one current worker at a time; parallel steps inside one task are not
  required.
- A claim is acquired atomically and identifies the worker execution allowed to
  report. Reports include the observed task version and current step. A stale
  claim, version, or step cannot change task state.
- Claims do not expire automatically in the MVP. Recovery uses an explicit,
  version-fenced takeover that invalidates the prior claim. KOS requires no
  lease clock, heartbeat, or automatic redispatch algorithm.
- Creating or replacing a not-yet-started task plan stores its tasks and
  dependencies atomically so workers never observe a partial plan.
- Incomplete blockers keep a dependent task unavailable. A task becomes ready
  when all of its blockers are complete.
- An accepted report stores the worker's result and applies its workflow
  transition atomically. Repeating a step replaces that step's latest accepted
  result; full attempt history is not required.
- Pause and answer state is durable and bound to the paused task step.
- The shared API credential is sufficient for the trusted single-installation
  MVP. Claims prevent conflicting writes; they are not user authorization.
- KOS skills describe available commands, role boundaries, and a small set of
  invariants. They do not encode shell, Git, locking, retry, review, testing, or
  publication algorithms that capable agents can determine from context.
- Skills and workflow instructions favor concise goals and observable
  postconditions over exhaustive negative rules or exact command sequences.
- KOS state, not a worker's conversational response, is authoritative progress
  for the orchestrator.
- Project-scoped discovery returns every unfinished plan and task needed for
  recovery. Completed state remains available through deliberate inspection.

# Errors

- Invalid workflow definitions, unknown transitions, stale reports, conflicting
  claims, and dependency cycles fail without a partial state change.
- A scheduler that finds no ready task reports that fact without creating
  speculative work.
- A worker that cannot make a material product decision pauses with one precise
  question instead of inventing the answer.
- A technical obstruction is recorded as a pause with its observed reason.
- A failed or ambiguous state mutation is resolved by rereading authoritative
  KOS state before another mutation; KOS does not require a prose retry
  algorithm.

# Edge Cases

- If a stale worker finishes after explicit takeover, its report is rejected by
  the changed claim or task version.
- If an orchestrator stops after dispatch, another orchestrator can discover
  the active task from the registered project and explicitly take it over after
  deciding the prior worker has stopped.
- If one parallel worker pauses or fails, unrelated ready tasks remain
  claimable.
- Corrective workflow outcomes may return to an earlier step. Workers decide
  which prior results remain relevant; KOS retains only the latest accepted
  result per executed step.
- Updating a reusable workflow creates a new revision for future tasks and does
  not change active or completed tasks.

# Acceptance Criteria

- A clean installation can store a project, a generic workflow, a task plan,
  dependencies, and task state without hand-editing application data.
- The main orchestrator can atomically claim multiple independent ready tasks
  and dispatch separate workers without performing their substantive steps.
- Two workers cannot successfully report the same claimed task version, and an
  explicitly superseded worker cannot change state.
- A worker can obtain all information needed to understand one current step and
  can atomically report one allowed result and transition.
- Pause, answer, completion, and the latest accepted step results survive a
  process restart.
- Given a registered project identity, a fresh orchestrator can discover every
  unfinished plan and task, including active claim fences and durable pause and
  answer state.
- Built-in and custom workflows execute through the same server transition
  rules without task-type-specific Git, check, review, or publication gates.
- Skills remain short enough to communicate capabilities, commands, role
  boundaries, and essential invariants without reproducing application logic.
- Automated tests prove storage, workflow validation, dependency readiness,
  atomic plan creation, claim/version fencing, transition atomicity, pause and
  answer persistence, and parallel claims on independent tasks.

# Non-goals

- KOS is not an agent runtime, process supervisor, reasoning engine, code-review
  judge, test runner, Git client, publication verifier, or security sandbox.
- KOS does not determine whether a diagnosis, implementation, test selection,
  review, Git operation, or publication is correct.
- The MVP does not require leases, heartbeat, automatic stale-worker detection,
  automatic retry, parallel steps within one task, multi-host coordination,
  multi-tenant authorization, high availability, or a web UI.
- The MVP does not require cryptographic Git-range evidence, server-enforced
  check results, model-output evaluation, full attempt history, or release
  attestation through live-model runs.
- KOS does not encode detailed deterministic procedures in skills merely to
  compensate for hypothetical mistakes by otherwise capable agents.

Implementation boundaries are refined in
[Architecture Rules](../docs/architecture.md), and verification layers and
commands are defined in [Testing Rules](../docs/testing.md). Those documents
describe the current implementation until the planned agent-led MVP
simplification is completed.
