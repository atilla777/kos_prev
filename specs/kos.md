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
- A main orchestrator creates or updates a task plan, preserves whether the user
  requested planning or execution, selects discovered workflows, claims ready
  tasks, starts workers, and observes authoritative state. It does not diagnose,
  implement, review, test, or publish task work itself.
- A worker agent performs exactly one current workflow step. Depending on the
  step, it may diagnose, plan, implement, select and run checks, review, use
  Git, or publish.
- An administrator registers projects and may define reusable workflows.

# User Scenarios

- The main orchestrator turns a goal into an ordered or dependency-linked plan
  of tasks and stores that plan in KOS.
- For an explicit planning-only goal, the orchestrator stores the complete plan
  and stops before ready-task discovery, claiming, takeover, or dispatch.
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
  the project's non-completed plans and tasks, reads their KOS state, and
  explicitly takes over unfinished work when appropriate.
- With explicit user intent, the orchestrator can atomically abandon an
  erroneous or obsolete started plan without erasing completed work.
- Built-in development, fix, and brief workflows may be supplied as convenient
  defaults, while custom workflows use the same generic state semantics.
- One generic `/kos` command handles planning and execution with built-in or
  custom workflows; retired workflow-specific command semantics are not implied.
- An administrator can discover workflow keys and immutable revisions, inspect
  the authoritative definition contract and example, and create a valid custom
  workflow using only the installed CLI.

# Rules

- KOS stores projects, immutable workflow revisions, tasks, task dependencies,
  current workflow position, claims, versions, pauses, answers, and the latest
  accepted result for each executed step.
- A task remains bound to the workflow revision selected when it is created.
- Built-in definitions are installed as an explicitly versioned catalog. A
  changed catalog creates new immutable workflow revisions for future tasks and
  leaves obsolete revisions available to tasks already using them.
- A workflow declares steps, concise instructions, allowed outcomes, and the
  transition associated with each outcome. KOS validates workflow shape and
  transitions but does not interpret instruction or result meaning.
- Built-in and custom workflows use the same transition mechanism. A step or
  task-type name gives the server no special Git, check, review, publication,
  graph, or completion semantics.
- The main orchestrator owns scheduling only: plan maintenance, ready-task
  selection, claiming, worker dispatch, pause presentation, takeover, and state
  observation. It never substitutes its own work for a worker step.
- Before storing new work, the orchestrator discovers available workflows. It
  selects `development` for ordinary implementation, `fix` for defect
  correction, `brief` for specification work, or the exact discovered custom
  workflow explicitly requested by the user.
- If an explicitly requested workflow is absent, the orchestrator asks one
  material question without creating or replacing coordination state. It does
  not guess a key, create a fallback workflow, or silently substitute one.
- Explicit planning-only intent authorizes one atomic plan write, not execution.
  After that write every task remains pending and unclaimed, and the
  orchestrator stops before even querying ready tasks.
- Worker execution requires execution intent. If planning versus execution is
  ambiguous, the orchestrator asks one material question before any ready-task
  query, claim, takeover, or dispatch.
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
- Cancelling a worker in the agent runtime does not mutate KOS, clear its claim,
  advance its version, or undo external effects. The orchestrator rereads
  authoritative task state before deciding whether takeover or any later claim
  release is still valid.
- Creating or replacing a not-yet-started task plan stores its tasks and
  dependencies atomically so workers never observe a partial plan.
- Each plan has an optimistic version advanced by every task lifecycle change.
  Abandoning a started plan requires the observed plan version and atomically
  marks every unfinished task abandoned, clears its claim, and advances its
  task version while preserving completed tasks and all accepted results.
- Abandoned plans and tasks are terminal and inspectable. They are never ready
  or claimable, and an abandoned blocker does not satisfy a dependency.
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
- Workflow definition validation, schema output, and CLI construction help share
  one authoritative contract rather than independent persisted or prose schemas.
- Project registration is an explicit administrator action over a published Git
  remote and chosen default branch. KOS derives a canonical host/path identity
  but does not create repositories, commits, branches, clones, or worktrees.
- Before installed OpenCode orchestration or worker execution, the supported
  integration compares its successful-install manifest, CLI, and server release
  identity and verifies server readiness.
- Skills and workflow instructions favor concise goals and observable
  postconditions over exhaustive negative rules or exact command sequences.
- KOS state, not a worker's conversational response, is authoritative progress
  for the orchestrator.
- Project-scoped discovery returns every non-completed plan and task needed for
  recovery, including terminal abandoned state. Completed state remains
  available through deliberate inspection.
- Coordination definitions and lifecycle text have documented finite byte and
  count limits. Oversized input is rejected without changing authoritative
  state, and accepted results are bounded both individually and in aggregate.

# Errors

- Invalid workflow definitions, unknown transitions, stale reports, conflicting
  claims, and dependency cycles fail without a partial state change.
- Oversized requests, definitions, results, pauses, and answers fail with stable
  errors and no partial state change.
- Stale or concurrent plan abandonment fails without partially abandoning the
  plan; claim, report, answer, takeover, and abandonment have one winner.
- A scheduler that finds no ready task reports that fact without creating
  speculative work.
- A missing explicitly requested workflow produces one material question and no
  workflow, plan, task, claim, or takeover mutation.
- A worker that cannot make a material product decision pauses with one precise
  question instead of inventing the answer.
- A technical obstruction is recorded as a pause with its observed reason.
- A failed or ambiguous state mutation is resolved by rereading authoritative
  KOS state before another mutation; KOS does not require a prose retry
  algorithm.
- Missing, invalid, stale, or mismatched installation metadata fails before
  project discovery or worker activity and directs the operator to reinstall all
  components from one release and restart OpenCode.
- A missing workflow, plan, task, or task result retains the stable `not_found`
  discriminator and identifies the missing resource and lookup value.

# Edge Cases

- If a stale worker finishes after explicit takeover, its report is rejected by
  the changed claim or task version.
- If a stale worker finishes after plan abandonment, its report is rejected by
  the abandoned status and advanced task version.
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
- A clean administrator can register and verify a published repository using
  the CLI, and a matching OpenCode manifest, CLI, and ready server pass one
  explicit preflight before orchestration.
- A clean administrator can list and inspect workflow revisions, print the
  workflow schema, and create a valid custom workflow using installed CLI help.
- The main orchestrator can atomically claim multiple independent ready tasks
  and dispatch separate workers without performing their substantive steps.
- An explicit planning-only goal leaves the atomically stored plan pending and
  unclaimed, while execution goals use an existing discovered workflow.
- Two workers cannot successfully report the same claimed task version, and an
  explicitly superseded worker cannot change state.
- A worker can obtain all information needed to understand one current step and
  can atomically report one allowed result and transition.
- Pause, answer, completion, and the latest accepted step results survive a
  process restart.
- Plan abandonment survives restart, preserves completed results, and remains
  distinguishable from successful completion during discovery.
- Given a registered project identity, a fresh orchestrator can discover every
  non-completed plan and task, including abandoned state, active claim fences,
  and durable pause and answer state.
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
- KOS does not abandon work automatically based on age or worker health and does
  not compensate or roll back external effects of abandoned work.
- The MVP does not require cryptographic Git-range evidence, server-enforced
  check results, model-output evaluation, full attempt history, or release
  attestation through live-model runs.
- KOS does not encode detailed deterministic procedures in skills merely to
  compensate for hypothetical mistakes by otherwise capable agents.

Implementation boundaries are refined in
[Architecture Rules](../docs/architecture.md), and verification layers and
commands are defined in [Testing Rules](../docs/testing.md). Those documents
describe the current implementation.
