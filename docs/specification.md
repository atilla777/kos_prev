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
- The main orchestrator creates or updates a plan, preserves planning-only or
  execution intent, selects an existing discovered workflow, selects ready
  tasks, claims them, dispatches workers, presents pauses, explicitly takes over
  stopped work, releases exact known cancelled dispatches, abandons erroneous
  or obsolete started plans with explicit user intent, and observes authoritative state.
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
- each plan's `active` or `abandoned` status and optimistic `version`;
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
The workflow definition schema is a read-only rendering of that same validation
contract and includes one complete valid example. It is not separately persisted
or versioned.

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

An explicit planning-only request authorizes discovery needed to construct the
plan and one atomic `plan put`, but not execution. After storing the plan, the
orchestrator stops before a ready-task query, claim, takeover, release, or worker
dispatch; all tasks remain pending and unclaimed. An execution request first
discovers available workflow keys and uses `development` for ordinary
implementation, `fix` for defect correction, `brief` for specification work, or
an exact discovered custom key explicitly requested by the user. If that
requested key is absent, the orchestrator asks one material question and makes
no coordination mutation. It never guesses a workflow key, creates a fallback,
or silently substitutes another workflow.

Worker execution requires execution intent. If planning versus execution is
ambiguous, the orchestrator asks one material question before any ready-task
query, claim, takeover, release, or worker dispatch.

`/kos` is the sole supported orchestration command. Selecting `brief` or another
workflow does not restore retired workflow-specific command behavior or imply
automatic creation of a follow-on implementation plan.

With explicit user intent, `plan abandon` retires one started plan using its
observed version. In one transaction it marks every unfinished task
`abandoned`, clears active claims, advances affected task versions, and marks
the plan abandoned. Completed tasks, accepted results, workflow history, and
pause/answer evidence remain available for inspection. Abandonment is terminal
and does not compensate external effects.

Dependencies must refer to tasks in the plan and must be acyclic. A pending task
is ready only when every blocker is complete. Paused, active, or otherwise
incomplete blockers do not satisfy readiness. Abandoned tasks are never ready
and do not satisfy dependencies. Failure or pause in one branch does not prevent
unrelated ready tasks from being claimed.

## Claims And Versions

`claim-id` generates an unpredictable non-secret value locally for one worker
dispatch. Claiming a ready task atomically installs that `claim_id`, activates
the task, and increments its optimistic `version`.

Claims do not expire. KOS has no lease duration, heartbeat, server-clock
comparison, stale-worker detector, or automatic redispatch. After deciding that
a worker stopped, the orchestrator performs `task takeover` with the observed
version and a new `claim_id`. A successful takeover increments the version and
invalidates the old worker.

Stopping or cancelling an OpenCode worker changes no KOS state and does not undo
external effects. Its claim remains active unless the worker already reported.
The orchestrator rereads authoritative task state after known cancellation and
before deciding whether to take over or later release the still-active claim.

Release is for an intentionally stopped dispatch without immediate replacement.
It requires the exact active `claim_id`, observed task `version`, and current
step. In one transaction it clears the claim, returns that same step to pending,
and advances task and plan versions. Takeover instead installs a replacement
claim immediately. Release is never inferred from age, inactivity, or worker
health and does not undo external effects.

Every lifecycle mutation supplies the observed task `version`. Worker reports
also supply the active `claim_id` and current step. A stale version, claim, or
step changes nothing. Consequently, two workers cannot both report the same task
version, and a worker superseded by takeover cannot change task state.

Every successful claim, takeover, release, answer, or report also advances the plan
version. Abandonment competes through that aggregate fence, so it and a
concurrent task mutation have one winner; successful abandonment invalidates
all claims and task versions for unfinished work.

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
supports numeric project reads for administration and inspection.

| CLI | API | Purpose |
| --- | --- | --- |
| `health` | `GET /up` | Public process liveness |
| `installation check` | `GET /ready` plus local manifest | Verify matching OpenCode, CLI, and ready server installation |
| - | `GET /ready` | Public database, migration, catalog, and data-directory readiness |
| `claim-id` | local | Create one dispatch claim identity |
| `project create`, `project show`, `project resolve`, `project update` | `POST /projects`, `GET /projects`, `PATCH /projects/:id` | Register, inspect, resolve from one selected local remote, and update project metadata |
| `status` | `GET /status?repository_identity=IDENTITY` | Return the resolved project's default non-completed recovery state |
| `workflow create` | `POST /workflows` | Create one immutable keyed revision |
| `workflow list` | `GET /workflows[?key=KEY]` | List keys and immutable revisions, optionally for one exact key |
| `workflow show ID` | `GET /workflows/:id` | Read one numeric immutable revision ID returned by the list |
| `workflow schema` | `GET /workflows/schema` | Read the authoritative definition contract and complete valid example |
| `plan list` | `GET /projects/:project_id/plans` | List non-completed plans, including abandoned state, or all plans when explicitly requested |
| `plan put`, `plan show` | `PUT /projects/:project_id/plan`, `GET /projects/:project_id/plan?key=KEY` | Atomically replace an unstarted plan and inspect it by key |
| `plan abandon` | `POST /projects/:project_id/plan/abandon` | Version-fence and atomically retire one started plan |
| `task list` | `GET /projects/:project_id/tasks` | List non-completed task state, including abandoned state, or all tasks when explicitly requested |
| `task ready` | `GET /tasks/ready?project_id=ID` | List dependency-ready tasks |
| `task show` | `GET /tasks/:id` | Observe lifecycle and fencing state |
| `task context` | `GET /tasks/:id/context` | Read one worker's complete current-step context |
| `task result` | `GET /tasks/:id/result?step=STEP` | Read one latest accepted result |
| `task claim` | `POST /tasks/:id/claim` | Claim a ready task |
| `task takeover` | `POST /tasks/:id/takeover` | Explicitly replace a stopped worker's claim |
| `task release` | `POST /tasks/:id/release` | Return one exact known stopped dispatch to pending without replacement |
| `task report` | `POST /tasks/:id/report` | Store one result and transition atomically |
| `task answer` | `POST /tasks/:id/answer` | Durably answer a paused step |

Only `/up` and `/ready` are public. Application operations require the bearer
token. Inputs are JSON or explicit file/standard-input values through the CLI.
Complete command help defines exact options and response fields. Failed
validation, dependency cycles, conflicting claims, and stale writes produce no
partial state change.
Missing workflow, plan, task, and task-result responses retain the stable
`not_found` discriminator and identify the resource and lookup value.

## Coordination Limits

All text limits are measured as valid UTF-8 bytes. The limits apply before an
API mutation can partially change authoritative state.

| Input or state | Limit |
| --- | ---: |
| JSON request body | 8 MiB |
| Keys, workflow step IDs, outcome names, and transition targets | 100 bytes each |
| Names, titles, and default branch names | 200 bytes each |
| Repository URLs and identities | 2 KiB each |
| Task descriptions, workflow instructions, pause messages, and answers | 16 KiB each |
| Claim IDs | 200 bytes each |
| Tasks in one plan | 64 |
| Dependencies in one plan | 256 total |
| Steps in one workflow revision | 64 |
| Outcomes in one workflow revision | 256 total |
| One accepted result | 1 MiB |
| Serialized latest accepted results for one task | 4 MiB total |

The aggregate result limit includes stored step and outcome keys plus JSON
encoding overhead. Reporting a repeated step replaces its prior result within
the same aggregate limit. These are trusted single-installation safety bounds,
not tenant quotas or rate limits.

## Recovery And Upgrade

Authoritative recovery starts with `status --remote REMOTE`. The CLI reads only
the explicitly named remote URL from the current Git checkout, normalizes it
with the registration identity rules, and requests the exact registered project
and its non-completed plans and tasks in one authenticated read. Missing Git,
checkout, remote, URL, registration, authentication, and transport state are
reported without a coordination mutation. The command never chooses a remote,
contacts it, or infers worker liveness.

Recovery state includes pending,
active, needs-human, blocked, and terminal abandoned state; active entries
expose their claim fence, released entries are ordinary pending unclaimed work,
and paused or abandoned entries retain persisted pause
and answer evidence. Completed state is excluded by default but can be requested
for deliberate inspection. Plan listings return identity, status, version, and
timestamps. Task listings return task and plan identity, `workflow_id`,
`workflow_key`, `workflow_revision`, task key, title, status, current step,
claim, version, pause and answer fields,
timestamps, and blocker IDs; per-command help names the exact fields.

After an ambiguous mutation, clients inspect the listing, `task show`,
`context`, or `result` before deciding whether another mutation is safe. KOS
does not require retained conversational identifiers, local receipts, pending
submission files, deterministic retry scripts, or automatic recovery. The
existing project-scoped list operations remain available for focused inspection.

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
web UI. KOS also excludes automatic age- or health-based abandonment and
compensation of external effects.
