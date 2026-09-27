# KOS Product Specification

Status: normative for the implemented PLAN-022 state-oriented architecture.

The OKF product concept is [`specs/kos.md`](../specs/kos.md). This document
defines the complete system contract and public protocol.

## Purpose And Boundary

KOS is a small task-state and coordination service for AI agents. It persists
projects, immutable workflow revisions, task types, tasks and descriptions,
parent and blocking relationships, current workflow position, ownership,
accepted step evidence, pauses, and answers. Rails and SQLite provide the
transactional state core; the thin `kos` CLI is the only agent interface to it.
Rails never starts OpenCode, Git, project checks, or agent processes.

The implemented built-in scenarios are:

```text
/kos-brief <request> -> brief -> review -> publish -> completed
/kos                 -> plan -> implement/check -> document -> review -> publish -> completed
/kos-fix <problem>   -> diagnose -> plan -> implement/check -> document -> review -> publish -> completed
```

The first version runs on one host with Rails, SQLite, the installed CLI,
OpenCode, KOS skills, and task worktrees. Parallel tasks use separate worktrees.
Moving an unfinished active task to another host is unsupported.

Users do not manage numeric project or task-type IDs, workflow IDs, claim
versions, leases, internal API calls, worktree paths, or workflow outcomes.
The CLI generates each command session's unpredictable non-secret owner ID. For
request-bound work, the server derives a deterministic bounded creation key and
immutable task definition from the command kind and exact request.
The shared bearer token authorizes every application operation and all token
holders are trusted. Owner IDs, leases, and claim-version fences provide
concurrency consistency among trusted holders, not per-agent authorization.
Database preparation idempotently installs the `brief`, `development`, and
`fix` task types and canonical workflows. Projects remain explicit
installation-specific registrations; custom workflows and task types remain
supported.

## Responsibilities

KOS is responsible for:

- five domain tables for projects, workflows, task types, tasks, and dependencies;
- immutable used workflows and each task's selected workflow revision;
- typed next-task selection, exact claims, and idempotent request create-or-get;
- exclusive leased ownership and monotonically increasing claim-version fencing;
- authoritative current-step context and focused accepted-artifact retrieval;
- validation of the reported step, outcome, artifact, closed required-check
  assertion, and pause message;
- atomic accepted-artifact storage and workflow transition;
- durable pause messages and exact human-answer binding;
- atomic validation and materialization of brief child graphs; and
- recovery after Rails, OpenCode, transport, or agent interruption.

KOS does not judge requirements, code, review findings, checks, Git history, or
Markdown meaning. It has no runtime broker, does not launch agents, and has no
dedicated Git SHA fields; SHAs may appear only as agent-authored Markdown evidence.
It has no universal arbitrary task-state blob, checkpoint,
attempt log, artifact graph, evaluation gate, or dual artifact source.

Agents and skills clarify tasks, execute steps, select and run project checks,
manage task worktrees, review independently, publish through Git, observe remote
results, and choose one allowed outcome from observed evidence.

## State-Oriented Execution

The slash-command skills are schedulers, not step executors. `/kos` resumes or
claims development work; `/kos-fix` and `/kos-brief` recover or atomically
create and claim their request-bound task. Once they have a positive task ID,
they retain only that ID. For every iteration a scheduler:

1. reads authoritative task context;
2. stops on `completed`, `needs_human`, or `blocked` as directed by persisted state;
3. reads the current step's authoritative `execution_mode` and `model_tier`;
4. executes a `main` step in the command agent, or launches one fresh generic
   standard or advanced subagent whose complete prompt is the task ID's decimal
   digits;
5. ignores child prose and claimed outcomes when a child was launched; and
6. rereads task context after either execution path, continuing only after an
   authoritative change in status, current step, claim version, or accepted
   evidence for the dispatched step.

An unchanged execution stops explicitly while its lease remains valid. If the
observed active claim has expired, one scheduler invocation may use the exact
observed claim version and step to resume it once, then dispatch that step at
most once more. A second required recovery, rejected or ambiguous resume, pause,
or terminal state stops without another dispatch.

The scheduler never receives or reads task Markdown, task description for
dispatch, workflow artifacts, Git diff, status, HEAD, project checks, child
   outcome text, local creation state, or pending submissions. It does not validate
artifacts, infer outcomes, report attempts, validate or materialize brief
children, or perform Git checks.

A step executor receives or retains only a positive task ID. It obtains
authoritative context and relevant accepted evidence itself, invokes `kos-git`
by task ID, and executes exactly one step within the workflow instruction. It reports its
complete artifact and selected transition itself. The server validates the
active owner, fence, current step, outcome, and artifact atomically; the agent
does not execute the next step.

For request-bound `/kos-fix` and `/kos-brief` work, the scheduler sends the
project, exact kind, exact request, and its fresh owner to `task create-or-get`.
The exact request is the byte sequence in OpenCode's `$ARGUMENTS` expansion.
Interactive slash-command payloads and `opencode run --command ...` requests
passed as separate argv words provide supported exact paths. OpenCode 1.18.26
display-serializes one argv containing spaces with wrapper quotes and escapes
literal quotes before expansion. KOS does not infer the originating argv or
guess, strip, or unescape that representation. The command, scheduler, CLI, and
server preserve the expansion through transport, hashing, and persistence.
The server derives the canonical title, description, and scoped SHA-256 creation
key. An identical retry returns the exact existing task without changing its
owner, status, lease, step, fence, or artifacts, so creation recovery needs no
local files.

## Data Model

The system has exactly five domain tables:

| Table | Required purpose and fields |
| --- | --- |
| `projects` | `id`, `name`, unique canonical `repository_identity`, `remote_url`, `default_branch`, timestamps |
| `workflows` | `id`, `name`, immutable `definition_json`, `created_at` |
| `task_types` | `id`, unique stable `key`, `name`, `workflow_id`, timestamps |
| `tasks` | `id`, `project_id`, `task_type_id`, `workflow_id`, optional `parent_id`, optional immutable `creation_key`, `title`, `description_markdown`, `status`, `current_step`, `owner_id`, `claim_version`, `lease_expires_at`, `accepted_artifacts`, `pause_message`, `pause_step`, `pause_claim_version`, `human_answer`, `human_answer_step`, `human_answer_claim_version`, timestamps |
| `task_dependencies` | `task_id` and `blocker_id` relationships with uniqueness and cycle rules |

A project stores no local checkout or worktree path. Its canonical identity is
`host/namespace/repository`; equivalent supported SSH and HTTPS `origin` URLs
normalize to that identity. Registration also stores the Git remote and a
Git-valid nonblank default branch. Rename or transfer updates the existing row,
preserving numeric identity and relationships.

Each workflow row is one complete immutable revision after use. A changed
definition creates a new row and repoints only the task type; existing tasks
retain their `workflow_id`. Task type keys are global and stable. The reserved
built-in keys are `brief`, `development`, and `fix`.

A pending task's description and dependencies may change before first claim.
After first claim its definition is fixed. Parents and blockers belong to the
same project and cannot create cycles; incomplete blockers prevent claims.
Non-null creation keys are unique by project and task type. Request-bound
create-or-get and keyed create-and-claim return an existing exact immutable definition without changing
its owner, status, lease, step, fence, or artifacts; a mismatch conflicts.

`accepted_artifacts` is the authoritative last accepted artifact map by step.
Each value contains the accepted `outcome`, complete `markdown`,
`accepted_claim_version`, and boolean `reconstructed`. Development and fix
implementation entries may additionally contain `required_checks`, whose closed
values are `passed`, `not_required`, `missing`, `blocked`, and `failed`.
Reporting a repeated step replaces that step's value. This JSON representation
is an implementation detail, not a universal task-state schema or attempt history.

## Workflow And Built-Ins

A workflow definition contains an ordered `steps` array. Every new step has a
unique `id`, `name`, `instruction`, `artifact_template`, `execution_mode` of
`main` or `subagent`, `model_tier` of `standard` or `advanced`, and an outcome
map. Unchanged persisted workflows without a mode execute as `subagent`, and
those without a tier execute as `advanced`. Every outcome has exactly one action:

- `next_step` naming an existing step;
- `pause` equal to `needs_human` or `blocked`; or
- `complete_task: true`.

KOS validates workflow shape and transitions but does not interpret evidence or
execute conditions. Every built-in step additionally supports `needs_human` and
`blocked`, which preserve the current step and pause. The exact non-pause routes
are:

### Development

| Step | Outcomes |
| --- | --- |
| `plan` | `planned` -> `implement` |
| `implement` | `implemented` -> `document`; `plan_invalid` -> `plan` |
| `document` | `documented` -> `review`; `implementation_invalid` -> `implement` |
| `review` | `approved` -> `publish`; `changes_requested` -> `implement`; `redesign_required` -> `plan` |
| `publish` | `published` -> complete; `review_invalid` -> `review`; `base_moved` -> `implement` |

### Fix

| Step | Outcomes |
| --- | --- |
| `diagnose` | `diagnosed` -> `plan` |
| `plan` | `planned` -> `implement`; `diagnosis_invalid` -> `diagnose` |
| `implement` | `implemented` -> `document`; `plan_invalid` -> `plan` |
| `document` | `documented` -> `review`; `implementation_invalid` -> `implement` |
| `review` | `approved` -> `publish`; `changes_requested` -> `implement`; `redesign_required` -> `plan` |
| `publish` | `published` -> complete; `review_invalid` -> `review`; `base_moved` -> `implement` |

### Brief

| Step | Outcomes |
| --- | --- |
| `brief` | `specified` -> `review` |
| `review` | `approved` -> `publish`; `changes_requested` -> `brief` |
| `publish` | `published` -> complete; `review_invalid` -> `review`; `base_moved` -> `brief`; `graph_invalid` -> `brief` |

Built-in diagnosis, planning, and review instructions require advanced,
read-only execution. Built-in briefing is advanced `main` execution and may
change only authorized specification and graph work. Briefing,
implementation, and documentation may create local task commits but never push;
each successful content step leaves a clean linear sequence from its observed
base to its tip, with exactly one raw canonical `KOS-Task: <task-id>` line and no
case variant or duplicate on every commit.
Implementation instructions own base integration and all required tests, lint,
formatting, builds, and type checks. Publication instructions are standard and
may only validate and push the approved sequence and, for a brief, materialize
children. Custom steps, including those whose IDs match built-in IDs, receive no
implicit authority from their names.

Briefing runs in the `/kos-brief` command agent and updates OKF behavior while
proposing a minimal acyclic graph. Review runs independently in a fresh advanced
subagent and checks both. Publication inspects the accepted graph, publishes the reviewed
specification, observes remote success, and then submits the exact graph to one
fenced operation that atomically normalizes, validates, digests, and materializes
it. Children are development tasks with the brief as parent and
blocker, plus declared sibling blockers. Only then does the publisher report
`published`, completing the brief.

## Ownership, Pauses, And Reporting

Statuses are `pending`, `active`, `needs_human`, `blocked`, `completed`, and
`cancelled`. `current_step` always identifies the next step to execute or retry.

Claiming atomically verifies readiness, sets `active`, records `owner_id`,
increments `claim_version`, and sets a server-time lease. Every execution
mutation supplies task ID, owner ID, claim version, and current step. Resume also
requires the exact persisted version and step, increments the version, and may
replace an expired owner or a confirmed stopped active owner. There is no
heartbeat.

For `needs_human`, reporting requires a nonblank `message`. The same transaction
stores it as `pause_message`, binds `pause_step` to the current step and
`pause_claim_version` to the incremented version, releases ownership, and stores
the accepted artifact. `blocked` uses the same exact binding for its technical
reason.

Resuming `needs_human` requires a nonblank valid UTF-8 answer together with the
persisted claim version and step. The transaction stores `human_answer`,
`human_answer_step`, and `human_answer_claim_version` equal to the paused step
and pause version, then activates and refences the task. Context returns the
answer only when those bindings match. A further active takeover preserves the
binding; the next accepted report clears pause and answer state atomically.

Every accepted report increments `claim_version`, even when a backward outcome
returns to the same step later. Pause and completion release ownership. A stale,
expired, duplicate, or wrong-step report cannot change artifact or transition
state.

## Context, Artifact, And Report Protocol

The focused public API routes are:

```text
GET  /tasks/:id/context
GET  /tasks/:id/artifact?step=STEP
POST /tasks/:id/report-attempt
```

The CLI exposes these as `task context`, `task artifact`, and
`task report-attempt`. Installed per-command help is authoritative for invocation
syntax and options.

`context` returns exactly these projections:

- `task`: `id`, `project_id`, `title`, `description_markdown`, `status`,
  `current_step`, `owner_id`, `claim_version`, and `lease_expires_at`;
- `project`: `id`, `name`, `repository_identity`, `remote_url`, and
  `default_branch`;
- `step`: `id`, `name`, `instruction`, `artifact_template`, `execution_mode`,
  `model_tier`, and `allowed_outcomes`;
- `artifacts`: one index entry per accepted step containing `step`, `outcome`,
  applicable `required_checks`, `accepted_claim_version`, and `reconstructed`,
  never Markdown; and
- `pause`: null or `step`, `claim_version`, `message`, and an `answer` only when
  exactly bound to that pause.

`artifact` requires one step and returns `outcome`, `markdown`, applicable
`required_checks`, `accepted_claim_version`, and `reconstructed`; an absent step
is not an empty artifact.

`report-attempt` accepts task ID plus top-level `owner_id`, `claim_version`,
`step`, `outcome`, `artifact`, optional `message`, and optional
`required_checks`. The CLI reads `artifact` from `--artifact-file`; `-` means
standard input. An artifact must be a nonempty valid UTF-8 string of at most 1
MiB. A pause message must be a nonblank string.
In one database transaction KOS validates the outcome and pause requirement,
checks active owner, unexpired lease, version, and current step, stores the last
accepted artifact, applies the transition, increments the fence, and clears or
sets pause/answer state. For built-in development and fix work,
`required_checks` is allowed only at implementation; `implemented` requires
`passed` or `not_required`. Positive review and publication also
require that assertion in accepted implementation evidence. Rails does not
select, run, or parse checks or their Markdown output. A built-in `complete_task`
action is rejected unless the reported step and outcome are `publish` and
`published`. For a brief at
`publish`, the transaction serializes with materialization, requires children
before accepting `published`, and rejects `base_moved`, `graph_invalid`, or
`review_invalid` after children exist. Rejection stores no artifact. It returns
the ordinary task envelope.

The broader CLI also exposes project create/show/update; workflow create; task
type create/update; task create/create-or-get/create-and-claim/update/show/show-owned;
claim-next, exact claim, resumable, exact resume, cancel; and brief graph
materialize/children operations. The installed CLI help lists exact
commands and options; the README summarizes the API routes and operational
setup.
`kos session-id` is a local unauthenticated operation that returns
`kos-session-` followed by 32 lowercase hexadecimal digits from a
cryptographically secure random source.
Public task-type administration may repoint custom types but cannot replace a
reserved built-in type's workflow; catalog installation owns built-in revisions.
`task create-or-get` accepts a project, kind `fix` or `brief`, owner, and exact
request file. `task create-and-claim` accepts optional `--creation-key KEY`;
ordinary task creation does not.

`kos health` calls the public `GET /up` endpoint selected by `KOS_API_URL`
without requiring `KOS_API_TOKEN`. Every application operation requires the
configured shared token. Its holders are trusted for all such operations;
ownership and fencing coordinate their concurrent writes but do not authorize
them separately.

## Recovery And Upgrade

Recovery uses authoritative current state, never local step files or attempt
history. After an ambiguous report, `context` and the accepted-artifact index
show whether the fenced transition occurred. An observed version, step, and
artifact prove acceptance; an unchanged matching fence permits at most one
careful retry; contradiction or unavailable observation blocks. The scheduler
does not retain artifact bytes or a pending submission. Its in-memory
before/after comparison bounds each unchanged execution, and expired-lease
recovery uses at most one exact fenced resume per invocation.

There is no `tasks/<id>/<step>.md`, answer sidecar, inode check, pre-dispatch
deletion, rename/fsync requirement, attempt marker, step receipt, or dual-read
fallback. Old local task artifacts are not read, imported, or considered
evidence.

This pre-release workflow change provides no general legacy migration or
dual-run path. The effective mode and tier defaults preserve already-persisted
immutable workflow revisions that omit those fields; other incompatible local
database state will be reset rather than translated.

Git recovery remains observation-oriented. Publication observes the approved
base, ordered commit sequence, tip, trees, paths, diff digest, and remote before retrying,
never force-pushes, and never duplicates a confirmed push. A moved base leaves
history and content unchanged and returns to implementation or briefing as the
workflow specifies; that content agent integrates before checks, documentation,
and review repeat. An ambiguous push is resolved by fetching and observing the
exact sequence remotely. Brief graph creation recovers by observing the complete
materialized graph and its server-derived digest.

## Publication

Briefing, implementation, and documentation may create local commits but never
push. Every commit in the task range contains exactly one raw canonical
`KOS-Task: <id>` line with no case variant or duplicate. Before a successful
content report the worktree and index are clean and
the commits form one linear, contiguous task-owned sequence from the observed
default-branch base to `HEAD`.

Review performs no repository mutation. It inspects the complete base-to-tip
diff, while its bounded approval records the exact base, ordered commit SHAs,
tip, base and per-commit tree identities, changed paths, and SHA-256 digest of
that diff. Approval is valid only while all of those facts and the clean
worktree remain unchanged.

The publisher validates accepted predecessor evidence and the exact approved
sequence, including successful structured required-check evidence for
development and fix tasks, then fetches the default branch. Invalid approval
returns `review_invalid`. After fetching, an exact reviewed remote tip and
sequence proves publication; an exact reviewed base permits the push; only a
remote differing from both permits `base_moved` or a conflict. A moved base
changes no history or content. Publication creates, amends, rebases, squashes,
cherry-picks, and appends no commit. It pushes the exact reviewed tip and range
without force, fetches regardless of push output, and reports success only after
observing the exact ordered sequence unchanged in remote history. A brief
publisher then atomically materializes its reviewed graph. The server will not
accept `published` until those children exist, and after they exist it permits a
technical `blocked` pause but no publication outcome that rewinds to briefing or
review.

The publisher reports `published` only after observing the exact reviewed range
in remote history and, for a brief, after the exact child graph exists. The server
then completes the task and releases ownership. Review and publication remain
separate steps; there is no built-in verifier step.

## Product Specifications

Participating projects may keep observable behavior in an OKF v0.2 `specs/`
bundle. The `okf` skill preserves unknown metadata and unrelated content and is
confined to that bundle. Rails stores accepted execution evidence but does not
parse or store the repository's OKF documents. Architecture and testing remain
technical contracts in `docs/`.

## Explicit Exclusions

The implemented version excludes cross-host active-task migration, a web UI,
multiple AI runtimes, a runtime broker, server-started OpenCode, heartbeat,
random claim tokens, checkpoints, a universal arbitrary task-state document,
full attempt history, artifact tables or graphs, result evaluators, candidate or
base SHA fields outside accepted Markdown evidence, condition
languages, parallel steps within one task, automatic conflict resolution,
force-push, automatic deletion of unknown worktrees, and Rails parsing of OKF.
