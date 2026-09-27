# Architecture Rules

These rules describe the implemented PLAN-022 state-oriented architecture.

## Boundaries

- Rails owns authoritative persistent state, validation, fencing, accepted
  artifacts, pause and answer bindings, and transactional transitions.
- The CLI is a thin authenticated HTTP client. It never reads SQLite directly
  and does not contain an agent runtime or broker.
- A slash-command orchestrator schedules from focused state: select or create, claim
  or resume, execute `main` steps locally or dispatch `subagent` steps by tier,
  and reread focused state.
- A main or subagent step executor owns one step: focused context reads,
  predecessor evidence, worktree operations, checks, artifact production,
  outcome choice, and reporting.
- The filesystem owns task worktrees. It does not own request-bound creation
  recovery, accepted step artifacts, or human answers.
- Git owns commits and SHA values. Rails has no Git-specific SHA fields. Content
  profiles may create local task history; only publication may mutate a remote.
- Product behavior lives in repository `specs/`; technical contracts live in
  `docs/`; accepted execution evidence lives in KOS task state.

## Design Rules

- Add mechanisms only for an end-to-end scenario and keep API projections focused.
- Enforce state invariants at the server boundary and within transactions, with
  database constraints where practical.
- Treat used workflow definitions as immutable values and keep concrete model
  identifiers in OpenCode profiles rather than workflow or task state.
- Derive machine-local worktree paths; never persist them as domain state.
- Require Rails and OpenCode to receive the same absolute `KOS_DATA_HOME` on
  their shared host; derive worktrees only below its `worktrees` directory.
- Keep external side effects outside Rails transactions and recover ambiguity by
  observing authoritative task, Git, remote, or child-graph state before retry.
- Keep liveness independent of dependencies. Readiness observes database access,
  migrations, canonical catalog state, and data-home writes without repairing them.
- Every local task commit is content-agent-owned, carries exactly one raw
  canonical task trailer line with no case variant or duplicate, and remains
  unpushed until publication; built-in tasks complete
  only after publication observes the reviewed remote range and graph results.
- Store only the last accepted artifact per step, not attempts, pending reports,
  receipts, or a universal arbitrary state object.
- Never use local artifact fallback, dual reads, or automatic import of legacy files.

## Components

### Rails State Core

The bearer-authenticated JSON API and SQLite database own projects, workflows,
task types, tasks, dependencies, and transitions. `GET /up` remains public.
The shared bearer token trusts its holders for every application operation.
Owner IDs, leases, and claim-version fences preserve concurrency consistency
among those holders; they are not authorization or an agent security boundary.
Public `/up` reports process liveness. Public `/ready` reports dependency
readiness with generic failures and the running version/source identity.
Rails validates workflow shape but does not select, execute, or interpret
planning, diagnosis, checks, documentation, review, publication,
or OKF. It enforces a closed required-check assertion at built-in delivery gates
without parsing check output or Markdown.

The five domain tables remain `projects`, `workflows`, `task_types`, `tasks`,
and `task_dependencies`. PLAN-022 adds execution context to `tasks`, not a new
artifact or attempt table. `accepted_artifacts` is a JSON map keyed by step ID;
each value contains `outcome`, complete `markdown`, `accepted_claim_version`,
and `reconstructed`. Development and fix implementation entries may also contain
the closed `required_checks` assertion. Approved brief review entries contain the
normalized `brief_graph` and server-derived `graph_digest`. Pause state uses `pause_message`,
`pause_step`, and `pause_claim_version`; answer state uses `human_answer`,
`human_answer_step`, and `human_answer_claim_version`.
Request-bound tasks may also store an immutable nullable `creation_key`. A
partial unique index on project, task type, and non-null key is the final
duplicate-creation boundary; ordinary tasks remain null and unaffected.

Each report transaction validates the artifact first, resolves the workflow
action, validates a required pause message, copies and updates the accepted map,
and performs one fenced update requiring active status, owner, claim version,
current step, and unexpired lease. The update stores the artifact, applies the
transition, increments `claim_version`, and sets or clears pause and answer state.
Built-in development and fix success at implementation, review, and publication
requires accepted `passed` or `not_required` check evidence.
No accepted artifact can exist without its corresponding accepted transition.
New workflow steps require explicit `execution_mode` and `model_tier`; unchanged
older revisions execute with effective `subagent` and `advanced` defaults where
those fields are absent. Public administration cannot repoint reserved built-in
task types; catalog installation owns their canonical workflow revisions.
Built-in completion is additionally constrained to the `published` outcome at
`publish`. Brief materialization performs bounded normalization and validation
before taking SQLite's writer lock. It then verifies the exact active publication
fence, compares with the accepted identity, and creates the graph in that
transaction. Materialization,
reporting, correction, and cancellation serialize. `published` requires observed
and approved graph digests to match. Exact retries are idempotent; `graph_invalid`
may atomically retract only an unclaimed pending graph, and cancellation terminates
unfinished children.

The artifact limit is 1 MiB by UTF-8 bytes. Artifacts must be nonempty valid
UTF-8 strings. KOS stores their exact Markdown but does not parse template
meaning. Repeating a step replaces that key; no attempt history is retained.

### CLI Transport

The packaged `kos` executable is stateless and preserves server response bodies.
Agents use only the administrator-configured absolute `KOS_CLI_PATH`. Top-level
and per-command help are the authoritative syntax reference. The shared
`kos-cli` skill protects credentials, supplies each value as a separate
argument, checks only response fields needed for the current decision, and
observes authoritative state before retrying an ambiguous mutation. Rails owns
response projections and lifecycle invariants; the CLI validates local options,
configuration, and input, then preserves server bodies.

The focused step operations are:

- `task context`, containing task execution identity, registered project,
  exact current step, artifact index, pause/answer projection, and status;
- `task artifact`, containing one accepted artifact; and
- `task report-attempt`, atomically accepting one
  artifact and transition.

`context` deliberately omits accepted Markdown from its artifact index. A step
agent separately requests only the artifacts it needs. Standard input is the
preferred source for structured content wherever command help supports it; task
content is never interpolated into shell syntax or stored as local protocol
state.

### Schedulers

`skills/kos` contains the shared scheduler for development, fix, brief, and
custom tasks; every slash command enters it directly. The scheduler may discover
a project, offer resumable tasks, request a safe claim or resume, and display
persisted pause information. `/kos-task` selects only existing custom work by an
exact stable type key and rejects reserved built-in keys.
The CLI generates one fresh unpredictable owner for each command session;
`KOS_OWNER_ID` is not configuration. Request-bound creation uses that owner in
the focused server-idempotent `task create-or-get` operation.

For each active iteration the scheduler reads the focused `task show` projection and follows only
the current step's `execution_mode` and `model_tier`. A `main` step executes in
the command agent through the shared step contract. A `subagent` step dispatches
one fresh generic standard or advanced child whose entire prompt is the decimal
task ID, then ignores all returned text. After either path the scheduler rereads
context and requires an authoritative change in status, step, claim version, or
the dispatched step's artifact-index entry before continuing. Unchanged valid
claims stop explicitly. An expired claim permits one exact fenced resume and at
most one retry in that invocation; a second recovery need stops. Scheduling
decisions never inspect task Markdown, accepted artifact bodies, Git state,
checks, child outcomes, graph proposals, receipts, or pending submissions. Step
execution, including reporting, remains a distinct phase.

Request-bound creation is one CLI and server operation. The scheduler supplies
the project, kind, fresh owner, and exact request. The server derives the
canonical title and description plus a scoped key from the request's SHA-256
digest, then uses the database unique index as the duplicate boundary. An
identical retry returns the existing task in any lifecycle state and never
reclaims or mutates it. No intent, lock, receipt, or legacy namespace is read or
written. The scheduler pipes the exact OpenCode `$ARGUMENTS` expansion to CLI
standard input without trimming or quote interpretation; the CLI and server
preserve those bytes through hashing and persistence. OpenCode 1.18.26
display-serializes one argv containing spaces with wrapper quotes and escaped
literal quotes before this boundary. KOS intentionally does not infer argv or
reverse that external representation. Interactive slash payloads and separate
`opencode run --command ...` argv words are the supported exact invocation paths.

### Step Execution

Every executor loads `kos-step` with exactly one positive task ID. The shared
guidance tells it to read authoritative context and relevant accepted evidence,
obtain its worktree through `kos-git`, execute one step, and report its own
result. Immediately before reporting, it rereads context and uses the active
task's owner, claim version, and current step as one fence; it does not create a
new session owner or substitute accepted-artifact versions. The workflow step's
instruction, artifact template, and outcomes are the complete substantive role
contract. Step IDs and profiles confer no authority.

The server transaction validates the active owner, claim version, current step,
outcome, artifact, and pause message and is the acceptance boundary. On an
ambiguous response the agent observes authoritative state through `kos-cli`.
The child returns only a non-authoritative confirmation and never performs a
second step.

### Git And Worktrees

`kos-git` accepts only a task ID, gets the registered project from context, and
requires the OpenCode process to have the same absolute `KOS_DATA_HOME` as
Rails. It derives `$KOS_DATA_HOME/worktrees/<project-id>/<task-id>` and
requires a verified detached worktree for the registered repository and remote,
preserves staged, unstaged, and untracked work, and refuses unknown or unsafe
paths and active Git operations rather than deleting or repairing them.

Repository discovery requires one `origin` fetch URL and one push URL. Supported
HTTPS, `ssh://git@...`, and relative scp-style `git@host:...` forms normalize to
one lower-cased-host `host/namespace/repository` identity. Credentials, ports,
queries, fragments, local paths, ambiguous slashes, non-`git` SSH users, and
fetch/push identity mismatches are rejected before mutation. `kos-cli` performs
an exact registration lookup. There is no `KOS_PROJECT_*` configuration.

`kos-git` supplies reusable discovery, verified worktree derivation, state
observation, and preservation rules. It does not infer read, commit, push,
review, publication, or graph authority from a step ID or task type; the
workflow instruction supplies those substantive boundaries.

## Execution Profiles

The slash commands run in OpenCode's primary `build` agent and load the shared
scheduler. `main` may be declared by any built-in or custom step, but command
frontmatter selects that agent's model before context is read. `/kos-task` uses
the advanced model for every custom `main` step; a main step's declared tier does
not dynamically replace it. `subagent` selection uses only `model_tier`:
`kos-step-standard` selects the standard model and `kos-step-advanced` selects
the advanced model. Built-in briefing is advanced `main`; its review is advanced
`subagent`, and publication is standard `subagent`.

Managed profiles intentionally contain no KOS-specific OpenCode permission
blocks or substantive role instructions. They select only model, reasoning
effort, and subagent mode. Tool approval comes from the administrator's OpenCode
configuration. The shared bearer token remains the authorization boundary;
lifecycle fencing coordinates trusted concurrent operations, while independent
review checks the resulting work.

## Backward Transitions

Focused agents validate predecessor evidence and use explicit correction routes:

- Development: `plan_invalid` to `plan`, `implementation_invalid` to
  `implement`, review `changes_requested` to `implement`, `redesign_required` to
  `plan`, and publish `review_invalid` to `review` or `base_moved` to `implement`.
- Fix adds plan `diagnosis_invalid` to `diagnose`; all later routes match
  development.
- Brief uses review `changes_requested` to `brief`; publish `review_invalid` to
  `review`, and `base_moved` or `graph_invalid` to `brief`. After materialization,
  only `graph_invalid` may rewind, retracting the safe graph in the same transaction.

Every built-in step also supports fenced `needs_human` and `blocked` pauses.
Backward execution replaces only artifacts for steps actually rerun. Later
accepted artifacts remain visible as historical last-accepted evidence, so each
step validates the exact predecessors and current repository state it relies on.

## Publication

Publication validates accepted plan, implementation, documentation, and review
evidence. Review inspects the complete aggregate diff and approval identifies
the exact base, ordered commit SHAs, tip, trees, paths, and SHA-256 diff digest
of a clean linear range whose every commit has one exact canonical `KOS-Task`
trailer line. A brief also validates its accepted
specification and graph. Publication first accepts an exact reviewed remote tip
and sequence as success, otherwise pushes only from the exact reviewed base. A
remote differing from both is a moved-base outcome or conflict; the publisher
changes nothing so briefing or implementation can integrate it and repeat the
downstream steps. Publication never
creates or rewrites history: it pushes the exact reviewed range without force
and reports `published` only after fetching and observing that exact sequence
remotely. Interrupted or ambiguous publication recovers from the same remote
observation. Brief children are atomically materialized only after remote
publication is observed.

`published` completes a built-in task and releases ownership. The publisher may
report it only after observing the expected remote commit and, for a brief, the
materialized child graph. There is no built-in verifier profile or scheduler
dispatch.

## Recovery And Migration

Task state is the recovery record. Server or OpenCode restart reads current
context and accepted artifacts. A lost report response is resolved by observing
the claim version, current step, status, and accepted-artifact index. There is no
local `tasks/<id>/<step>.md`, answer sidecar, pre-dispatch unlink, inode identity,
rename/fsync rule, marker, attempt ID, report receipt, pending submission, or
dual-read compatibility path.

Resume is fenced by exact claim version and step. A `needs_human` answer is
stored against the pause's step and incremented pause version; context projects
it only for that exact binding. The binding survives another active takeover and
is cleared by the next accepted report.

This pre-release workflow change provides no general legacy migration or
dual-run path. Effective execution defaults preserve immutable workflow
revisions that omit mode or tier; other incompatible local database state is
reset rather than translated or repointed. Legacy local files remain ignored.

Scoped server creation keys recover request creation through an identical
create-or-get retry. Git publication and brief materialization ambiguity are
recovered from remote Git and complete server graph observations respectively,
never from local protocol files.

Production is one systemd-supervised, loopback-bound Puma process behind a TLS
proxy. SQLite backup uses its online backup command while application writers
are stopped, then integrity, foreign-key, and isolated restore checks. Database
rollback and application rollback are one decision after migrations; task
worktrees and source repositories remain separate Git recovery state.

See [the system specification](specification.md), [testing rules](testing.md),
and [installation guide](installation.md).
