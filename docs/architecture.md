# Architecture Rules

## Boundaries

- Rails and SQLite own authoritative projects, immutable workflow revisions,
  atomic plans, plan status and versions, dependencies, task state, claims,
  versions, pauses, answers, latest accepted results, and generic transitions.
- The packaged CLI is a thin authenticated HTTP client. `claim-id` is its only
  local state-producing operation.
- The `/kos` main agent is an orchestrator. It plans, finds ready tasks, claims
  them, dispatches `kos-worker`, presents pauses, performs explicit takeover or
  exact release of its known cancelled dispatch, and observes state. It performs
  no substantive workflow step.
- Explicit planning-only intent ends orchestration immediately after atomic plan
storage, before ready discovery or any lifecycle mutation. Workflow selection
is based on discovery and user intent, never a guessed key or fallback
definition. Ambiguous planning-versus-execution intent is clarified before any
ready-task query or worker lifecycle mutation.
- A `kos-worker` agent reads authoritative context, performs exactly one current
  step, reports one outcome, and stops.
- Workflow instructions grant substantive authority. The application and skills
  do not infer special behavior from built-in, task, step, or outcome names.
- External effects such as repository changes, checks, review, Git, and
  publication belong to workers when a workflow instruction permits them. KOS
  neither performs nor validates those effects.

## State Core

Projects identify registered repositories and contain task plans. Each workflow
registration creates an immutable keyed revision. Tasks retain the revision
chosen when their plan is stored, so later revisions cannot alter active or
completed work. The source-controlled built-in catalog declares its current
revision; idempotent seeding installs that revision without changing obsolete
revisions, and readiness requires the current catalog rather than comparing old
revisions with current source definitions.

`plan put` validates the complete proposed task set and dependency graph before
one transaction creates or replaces it. Replacement is rejected after any task
starts. Dependencies are acyclic, and readiness is derived from completion of
all blockers rather than maintained by an agent-side graph algorithm.

A started plan can be abandoned only through its observed aggregate version.
Every task lifecycle mutation advances that version. Abandonment atomically
marks all unfinished tasks terminal, clears claims, and advances their versions
while preserving completed tasks and all inspection state. It does not undo
repository, Git, or other external effects.

Each task has an optimistic integer `version` and at most one active `claim_id`.
Claim, takeover, release, answer, and report use compare-and-change transactions. Claims
are non-expiring. Explicit takeover with the observed version installs a new
claim and makes every prior worker stale; there is no lease or time-dependent
state transition.

An accepted report and its transition are inseparable. One transaction checks
the claim, version, current step, and allowed outcome, replaces that step's
latest result, applies the workflow action, updates pause/answer state, and
increments the version. No attempt log or generic arbitrary state document is
required.

Pause state contains the paused step and one worker-authored question or
technical obstruction. Pausing releases the claim. Answer state is durably
bound to that pause, survives restart, and makes the same step claimable again.
Both are cleared only by an accepted report for the paused step.

## API And CLI

The public command families are:

```text
health
claim-id
installation check
project create|show|resolve|update
status
workflow create|list|show|schema
plan put|list|show|abandon
task list|ready|show|context|result|claim|takeover|release|report|answer
```

The JSON API mirrors these operations with public `GET /up` liveness and
`GET /ready` dependency readiness probes, project resources,
immutable workflow discovery and creation, the read-only workflow schema and
aggregate recovery status,
project-scoped plan storage and abandonment,
ready-task discovery, project-scoped non-completed-state discovery, task reads,
and task claim/takeover/report/answer mutations. The CLI validates local arguments and
input, sends one request, preserves server output, and does not duplicate
workflow or recovery policy. Per-command help is the syntax authority.

`installation check` is one local exception to ordinary API
mapping. It validates the OpenCode successful-install manifest, compares its
version and source identity with the packaged CLI, then compares both with the
public `/ready` response. Exact equality is intentional for the single-release
pre-release deployment; KOS has no mixed-release compatibility matrix.

Current-checkout recovery is the other narrow local exception. `project resolve`
and `status` read the URL of one caller-selected Git remote and normalize it with
the shared repository identity implementation before one authenticated request.
They do not select or contact remotes, fetch, inspect branches, or manage Git
state. Status composes authoritative project, plan, and task projections in one
read-only server operation and adds no persisted aggregate model.

`task show` is the orchestrator's focused lifecycle view. `task context` is the
worker view and includes the current immutable instruction, outcomes, prior
result index, and bound pause/answer. `task result` retrieves one latest accepted
result body separately.

All definition writes are all-or-nothing. All lifecycle writes use the observed
version; report additionally requires the current `claim_id` and step. Stable
validation and conflict errors let agents reread authoritative state without
requiring an encoded retry algorithm.
Workflow schema output and workflow creation help derive from the same pure-Ruby
contract used by model validation. The schema is read-only application data, not
a persisted resource or workflow lifecycle. Missing-resource responses preserve
the stable discriminator while naming the resource and lookup value.

Finite count and UTF-8 byte limits bound request bodies, definitions, lifecycle
text, and accepted-result state. Plan cycle detection is iterative and bounded
by the plan task and dependency limits. Aggregate accepted-result validation is
part of the report transaction, before task or plan versions advance. The exact
public limits are listed in [the system specification](specification.md).

Plan abandonment uses the observed plan version. It shares one transactional
plan fence with claim, report, answer, takeover, and release, so concurrent operations
have one winner and cannot expose partially abandoned state.

## Agent Integration

The managed OpenCode inventory is one `/kos` command, one `kos-worker` agent,
and skills `kos`, `kos-cli`, `kos-worker`, and `okf`.

The generic `/kos` command discovers workflow keys before planning execution. It
uses the existing `development`, `fix`, or `brief` workflow for ordinary
implementation, defect correction, or specification work respectively, and an
exact discovered custom key when explicitly requested. An absent requested key
causes one material question and no coordination mutation. Workflow selection
does not recreate retired workflow-specific slash commands.

Both the orchestrator and independently invoked workers run `installation
check` before project or task access. A missing or invalid manifest, inventory
or release mismatch, or unavailable server stops execution before repository or
coordination changes. Replacing installed files requires a full OpenCode restart
because a running process may retain previously loaded assets.

The orchestrator may claim several independent ready tasks and dispatch one
worker per task concurrently. It passes only the identity needed for the worker
to obtain authoritative context. It does not inspect results to reproduce a
workflow step, execute a `main` step, or advance state on a worker's behalf.

Only explicit user intent authorizes the orchestrator to abandon a started
plan. A stopped worker alone calls for observation or takeover; workers never
abandon plans.

The worker chooses its tools and detailed procedure from the workflow
instruction and repository context. It reports with the immutable claim
envelope supplied for that dispatch and never adopts a later claim, version, or
step. It reports its own result and never executes the next step. Skills remain
concise capability and boundary guidance; they do not encode shell, Git,
locking, retry, review, test, or publication algorithms.

## Concurrency And Recovery

Independent tasks can be claimed in parallel. Serial transactions and
optimistic versions prevent duplicate claims and stale reports for the same
task. KOS does not support parallel workers or parallel steps within one task.

Recovery is observational. A new orchestrator uses one explicitly selected
checkout remote to resolve a registered project and read its unfinished plans
and tasks, and may take over an active task only
after deciding the prior worker stopped. Discovery returns persisted lifecycle
and pause state; it does not infer readiness, staleness, or takeover policy. A
delayed worker's report fails because takeover changed both claim identity and
task version. An ambiguous mutation is resolved by reading current state before
another write.

Runtime cancellation of a worker is not a KOS mutation: it does not clear the
claim, advance the version, or undo external effects. After known cancellation,
the orchestrator rereads the task because the worker may have reported before it
stopped, and only then decides whether a still-active claim should be taken over
or later released. Release requires the exact cancelled dispatch envelope and
returns the same step to pending; takeover installs an immediate replacement.

Successful abandonment similarly invalidates every unfinished worker. Terminal
abandoned records remain in default non-completed discovery but are never ready
or eligible for lifecycle mutations.

There are no leases, heartbeat, clocks, owner sessions, automatic stale-worker
detection, request creation keys, local protocol files, or pending-report
receipts.

Project registration is administrator-owned. The server normalizes a supported
Git remote into the durable repository identity and stores the selected default
branch. Outside the focused recovery inspection above, neither server nor CLI
inspects a checkout. Neither chooses a remote, creates GitHub resources,
publishes an initial branch, clones, or manages worktrees. OpenCode must run in
the intended existing checkout.

## Deployment And Upgrade

The supported MVP deployment is one Rails process with local SQLite and a shared
bearer token. `GET /up` is public process liveness and `GET /ready` is public
dependency readiness; application operations are authenticated. SQLite must
reside on local storage and should be backed up with SQLite's online backup
operation while writers are stopped.

The agent-led schema is a pre-release compatibility break. Upgrades reset the
database rather than migrating PLAN-022 state. An operator may preserve a backup
for reference, but must recreate projects, workflows, and plans in the new
database. No legacy migration, dual read, or automatic import is promised.

See [the system specification](specification.md), [testing rules](testing.md),
and [installation guide](installation.md).
