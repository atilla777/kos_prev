# KOS Product Specification

This document refines the approved product contract in
[`specs/kos.md`](../specs/kos.md).

## Purpose

KOS is an authoritative store for task plans, reusable workflows, and current
task state. It provides only the durable coordination and concurrency controls
needed by cooperating agents. It is not an agent runtime, process supervisor,
reasoning engine, test runner, Git client, reviewer, or publisher.

The trusted single-installation MVP uses one shared bearer credential. Claims
coordinate writes; they are not identities for authorization.

## Roles

- The user supplies a goal and answers material questions.
- The main orchestrator creates or updates a plan, selects ready tasks, claims
  them, dispatches workers, presents pauses, explicitly takes over stopped work,
  and observes authoritative state.
- A worker performs exactly one current workflow step. It chooses the reasoning,
  tools, checks, repository operations, and evidence appropriate to that step,
  reports one allowed outcome, and stops.
- An administrator registers projects and reusable workflows.

The orchestrator never substitutes its own diagnosis, implementation, testing,
review, Git work, or publication for a worker step. It may dispatch workers for
multiple independent tasks concurrently. A single task has one current step and
at most one current worker.

## Durable Model

KOS stores:

- projects identified by registered repository identity;
- immutable workflow revisions;
- project-scoped task plans containing task definitions and dependencies;
- each task's selected workflow revision, current step, status, and optimistic
  `version`;
- one optional non-expiring active `claim_id`;
- durable pause and answer state bound to the current step; and
- the latest accepted result for each executed step.

A workflow revision declares its steps, concise worker instructions, allowed
outcomes, and one transition for each outcome. A transition moves to another
step, pauses with `needs_human` or `blocked`, or completes the task. KOS validates
workflow shape and references but never interprets instruction or result
meaning.

Built-in workflows are convenient defaults and use exactly the same transition
mechanism as custom workflows. Workflow, step, and outcome names confer no
special task-type, Git, check, review, graph, publication, or completion rules.
The built-in catalog has an explicit source revision, and installing a changed
catalog creates new immutable workflow revisions. Updating any workflow creates
a revision for future tasks; existing tasks remain bound to their selected
revision.

## Plans And Readiness

`plan put` validates and stores the complete plan in one transaction, including
all task definitions and blocker relationships. No reader can observe a partial
plan. A plan may be replaced only while none of its tasks has started.

Dependencies must refer to tasks in the plan and must be acyclic. A pending task
is ready only when every blocker is complete. Paused, active, or otherwise
incomplete blockers do not satisfy readiness. Failure or pause in one branch
does not prevent unrelated ready tasks from being claimed.

## Claims And Versions

`claim-id` generates an unpredictable non-secret value locally for one worker
dispatch. Claiming a ready task atomically installs that `claim_id`, activates
the task, and increments its optimistic `version`.

Claims do not expire. KOS has no lease duration, heartbeat, server-clock
comparison, stale-worker detector, or automatic redispatch. After deciding that
a worker stopped, the orchestrator performs `task takeover` with the observed
version and a new `claim_id`. A successful takeover increments the version and
invalidates the old worker.

Every lifecycle mutation supplies the observed task `version`. Worker reports
also supply the active `claim_id` and current step. A stale version, claim, or
step changes nothing. Consequently, two workers cannot both report the same task
version, and a worker superseded by takeover cannot change task state.

## Context, Results, And Reporting

`task context` returns everything a worker needs for one step:

- task identity, description, status, current step, version, and active claim;
- project information;
- the immutable workflow revision and current step instruction;
- allowed outcomes and transitions;
- an index of available prior results; and
- the current pause question or obstruction and its exactly bound answer.

`task result` returns the latest accepted result for one executed step. Results
are opaque worker-authored content plus the reported outcome; KOS does not parse
or judge their semantic claims. If a workflow returns to a step and that step is
reported again, the new accepted result replaces the previous result for that
step. Full attempt history is not required.

`task report` atomically validates the active claim, observed version, current
step, and allowed outcome; stores the latest result; applies the declared
transition; and increments the version. A pause outcome also stores one nonblank
question or concrete obstruction and releases the claim. Completion also
releases the claim. A worker never executes the resulting next step.

`task answer` stores a nonblank answer against the exact paused step and observed
version, then makes that same step available for a new claim. The pause and
answer survive process restarts and remain visible in context until the step
reports an accepted result. Answering does not allow a stale worker to report.

## Public Operations

The CLI exposes the focused agent-facing capabilities below. The API also
supports numeric project reads plus workflow revision listing and reads for
administration and inspection.

| CLI | API | Purpose |
| --- | --- | --- |
| `health` | `GET /up` | Public process liveness |
| `claim-id` | local | Create one dispatch claim identity |
| `project create`, `project show`, `project update` | `POST /projects`, `GET /projects`, `PATCH /projects/:id` | Register, inspect, and update project metadata |
| `workflow create` | `POST /workflows` | Create one immutable keyed revision |
| `plan list` | `GET /projects/:project_id/plans` | List unfinished plans, or all plans when explicitly requested |
| `plan put`, `plan show` | `PUT /projects/:project_id/plan`, `GET /projects/:project_id/plan?key=KEY` | Atomically replace an unstarted plan and inspect it by key |
| `task list` | `GET /projects/:project_id/tasks` | List unfinished task lifecycle state, or all tasks when explicitly requested |
| `task ready` | `GET /tasks/ready?project_id=ID` | List dependency-ready tasks |
| `task show` | `GET /tasks/:id` | Observe lifecycle and fencing state |
| `task context` | `GET /tasks/:id/context` | Read one worker's complete current-step context |
| `task result` | `GET /tasks/:id/result?step=STEP` | Read one latest accepted result |
| `task claim` | `POST /tasks/:id/claim` | Claim a ready task |
| `task takeover` | `POST /tasks/:id/takeover` | Explicitly replace a stopped worker's claim |
| `task report` | `POST /tasks/:id/report` | Store one result and transition atomically |
| `task answer` | `POST /tasks/:id/answer` | Durably answer a paused step |

Application operations require the bearer token. Inputs are JSON or explicit
file/standard-input values through the CLI. Complete command help defines exact
options and response fields. Failed validation, dependency cycles, conflicting
claims, and stale writes produce no partial state change.

## Recovery And Upgrade

Authoritative recovery starts by resolving the registered project and listing
its unfinished plans and tasks. These project-scoped reads include pending,
active, needs-human, and blocked tasks; active entries expose their claim fence,
and paused entries expose their persisted question or obstruction and bound
answer. Completed state is excluded by default but can be requested for
deliberate inspection. `plan list` returns plan identity and timestamps. `task
list` returns task and plan identity, workflow identity, key, title, status,
current step, claim, version, pause and answer fields, timestamps, and blocker
IDs; per-command help names the exact fields.

After an ambiguous mutation, clients inspect the listing, `task show`,
`context`, or `result` before deciding whether another mutation is safe. KOS
does not require retained conversational identifiers, local receipts, pending
submission files, deterministic retry scripts, or automatic recovery.

This pre-release architecture does not migrate PLAN-022 databases. Upgrade is a
destructive reset: optionally retain a backup for reference, remove the old KOS
database, prepare a new one, then recreate projects, workflows, and plans. Legacy
tasks, task types, leases, artifacts, request keys, and brief graphs are not
translated or imported.

## Non-Goals

The MVP excludes leases, heartbeat, automatic retries, parallel steps within one
task, request-bound commands, task types, main-agent step execution, server-side
required-check gates, Git/review/publication validation, brief graphs,
deterministic scheduler or Git algorithms, live-model release gates,
multi-tenant authorization, high availability, multi-host coordination, and a
web UI.
