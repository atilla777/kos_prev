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
/kos-brief <request> -> brief -> review -> publish -> verify -> completed
/kos                 -> plan -> implement/check -> document -> review -> publish -> verify -> completed
/kos-fix <problem>   -> diagnose -> plan -> implement/check -> document -> review -> publish -> verify -> completed
```

The first version runs on one host with Rails, SQLite, the installed CLI,
OpenCode, KOS skills, and task worktrees. Parallel tasks use separate worktrees.
Moving an unfinished active task to another host is unsupported.

Users do not manage numeric project or task-type IDs, workflow IDs, claim
versions, leases, internal API calls, worktree paths, or workflow outcomes.
Each command session generates its own unpredictable non-secret owner ID;
request-bound creation persists its unique owner before task creation.
It also derives a deterministic bounded creation key from the command kind and
exact request digest.
Database preparation idempotently installs the `brief`, `development`, and
`fix` task types and canonical workflows. Projects remain explicit
installation-specific registrations; custom workflows and task types remain
supported.

## Responsibilities

KOS is responsible for:

- five domain tables for projects, workflows, task types, tasks, and dependencies;
- immutable used workflows and each task's selected workflow revision;
- typed next-task selection, exact claims, and idempotent create-and-claim;
- exclusive leased ownership and monotonically increasing claim-version fencing;
- authoritative current-step context and focused accepted-artifact retrieval;
- validation of the reported step, outcome, artifact, and pause message;
- atomic accepted-artifact storage and workflow transition;
- durable pause messages and exact human-answer binding;
- atomic validation and materialization of brief child graphs; and
- recovery after Rails, OpenCode, transport, or agent interruption.

KOS does not judge requirements, code, review findings, checks, Git history, or
Markdown meaning. It has no runtime broker, does not launch agents, and does not
store Git SHAs. It has no universal arbitrary task-state blob, checkpoint,
attempt log, artifact graph, evaluation gate, or dual artifact source.

Agents and skills clarify tasks, execute steps, select and run project checks,
manage task worktrees, review independently, publish through Git, verify remote
results, and choose one allowed outcome from observed evidence.

## State-Oriented Execution

The slash-command skills are schedulers, not step executors. `/kos` resumes or
claims development work; `/kos-fix` and `/kos-brief` recover or atomically
create and claim their request-bound task. Once they have a positive task ID,
they retain only that ID. For every iteration a scheduler:

1. reads authoritative task context;
2. stops on `completed`, `needs_human`, or `blocked` as directed by persisted state;
3. maps the exact current built-in step to its focused profile, or an unknown
   custom step's tier to the generic standard or advanced profile;
4. launches one fresh foreground step agent whose complete prompt is the task
   ID's decimal digits; and
5. ignores child prose and claimed outcomes, then rereads task context.

The scheduler never receives or reads task Markdown, task description for
dispatch, workflow artifacts, Git diff, status, HEAD, project checks, child
outcome text, creation receipts, or pending submissions. It does not validate
artifacts, infer outcomes, report attempts, validate or materialize brief
children, or perform Git checks.

A fresh step agent receives only a positive task ID. It obtains the exact
current context itself, requires an active unexpired claim, and validates the
step, instruction, template, outcomes, project, owner, and claim version. It
separately fetches only accepted predecessor artifacts needed for the current
step, validates them, and selects an explicit backward outcome when evidence is
invalid. It invokes `kos-git` by task ID, executes exactly one step within its
profile, rereads context to confirm the same fence, and reports its complete
artifact and transition itself. It never executes the next step.

Creation intents, locks, and receipts are owned by the installed `kos-create`
pre-ID procedure for request-bound `/kos-fix` and `/kos-brief` creation. It binds
the exact request, canonical definition, unique owner, deterministic creation
key, and SHA-256 digest in a
private project/type/request namespace until it can return only a confirmed
positive task ID. It uses only `kos-cli`, recovers ambiguity by exact owned-task
observation, and durably binds the request to the confirmed ID. The scheduler
does not receive or inspect those files, and they are never step inputs or an
alternative source of workflow progress.

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
Non-null creation keys are unique by project and task type. Keyed
create-and-claim returns an existing exact immutable definition without changing
its owner, status, lease, step, fence, or artifacts; a mismatch conflicts.

`accepted_artifacts` is the authoritative last accepted artifact map by step.
Each value contains exactly the accepted `outcome`, complete `markdown`,
`accepted_claim_version`, and boolean `reconstructed`. Reporting a repeated
step replaces that step's value. This JSON representation is an implementation
detail, not a universal task-state schema or attempt history.

## Workflow And Built-Ins

A workflow definition contains an ordered `steps` array. Every step has a
unique `id`, `name`, `instruction`, `artifact_template`, `model_tier` of
`standard` or `advanced`, and an outcome map. Persisted legacy workflows without
a tier execute as `advanced`. Every outcome has exactly one action:

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
| `publish` | `published` -> `verify`; `review_invalid` -> `review`; `base_moved` -> `implement` |
| `verify` | `verified` -> complete; `publication_missing` -> `publish`; `changes_invalid` -> `implement` |

### Fix

| Step | Outcomes |
| --- | --- |
| `diagnose` | `diagnosed` -> `plan` |
| `plan` | `planned` -> `implement`; `diagnosis_invalid` -> `diagnose` |
| `implement` | `implemented` -> `document`; `plan_invalid` -> `plan` |
| `document` | `documented` -> `review`; `implementation_invalid` -> `implement` |
| `review` | `approved` -> `publish`; `changes_requested` -> `implement`; `redesign_required` -> `plan` |
| `publish` | `published` -> `verify`; `review_invalid` -> `review`; `base_moved` -> `implement` |
| `verify` | `verified` -> complete; `publication_missing` -> `publish`; `changes_invalid` -> `implement` |

### Brief

| Step | Outcomes |
| --- | --- |
| `brief` | `specified` -> `review` |
| `review` | `approved` -> `publish`; `changes_requested` -> `brief` |
| `publish` | `published` -> `verify`; `review_invalid` -> `review`; `base_moved` -> `brief`; `graph_invalid` -> `brief` |
| `verify` | `verified` -> complete; `publication_missing` -> `publish`; `materialization_missing` -> `publish`; `brief_invalid` -> `brief` |

Diagnosis, planning, review, and verification are advanced and read-only.
Briefing is advanced and may change only authorized specification and graph
work. Implementation and documentation are standard, may change the worktree,
and may not commit or push. Implementation owns all required tests, lint,
formatting, builds, and type checks. Publication is standard and is the only
authority allowed to update a moved base, stage, commit, push, and, for a brief,
materialize children. Unknown custom steps use tier-specific profiles that may
not commit or push.

Briefing is a fresh isolated step, not work performed in the main conversation.
It updates OKF behavior and proposes a minimal acyclic graph. Review independently
checks both. Publication validates the accepted graph, publishes the reviewed
specification, observes remote success, and then atomically materializes the
exact graph. Children are development tasks with the brief as parent and
blocker, plus declared sibling blockers. Verification independently compares
the remote specification and server-observed graph with accepted evidence.

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

The focused public operations are:

```text
GET  /tasks/:id/context
GET  /tasks/:id/artifact?step=STEP
POST /tasks/:id/report-attempt

kos task context ID
kos task artifact ID --step STEP
kos task report-attempt ID --owner-id OWNER --claim-version VERSION \
  --step STEP --outcome OUTCOME --artifact-file FILE [--message MESSAGE]
```

`context` returns exactly these projections:

- `task`: `id`, `project_id`, `title`, `description_markdown`, `status`,
  `current_step`, `owner_id`, `claim_version`, and `lease_expires_at`;
- `project`: `id`, `name`, `repository_identity`, `remote_url`, and
  `default_branch`;
- `step`: `id`, `name`, `instruction`, `artifact_template`, `model_tier`, and
  `allowed_outcomes`;
- `artifacts`: one index entry per accepted step containing `step`, `outcome`,
  `accepted_claim_version`, and `reconstructed`, never Markdown; and
- `pause`: null or `step`, `claim_version`, `message`, and an `answer` only when
  exactly bound to that pause.

`artifact` requires one step and returns exactly `outcome`, `markdown`,
`accepted_claim_version`, and `reconstructed`; an absent step is not an empty
artifact.

`report-attempt` accepts task ID plus top-level `owner_id`, `claim_version`,
`step`, `outcome`, `artifact`, and optional `message`. The CLI reads `artifact`
from `--artifact-file`; `-` means standard input. An artifact must be a nonempty
valid UTF-8 string of at most 1 MiB. A pause message must be a nonblank string.
In one database transaction KOS validates the outcome and pause requirement,
checks active owner, unexpired lease, version, and current step, stores the last
accepted artifact, applies the transition, increments the fence, and clears or
sets pause/answer state. A built-in `complete_task` action is rejected unless the
reported step is `verify`, including immutable legacy snapshots. For a brief at
`publish`, the transaction serializes with materialization, requires children
before accepting `published`, and rejects `base_moved`, `graph_invalid`, or
`review_invalid` after children exist. Rejection stores no artifact. It returns
the ordinary task envelope.

The broader CLI also exposes project create/show/update; workflow create; task
type create/update; task create/create-and-claim/update/show/show-owned;
claim-next, exact claim, resumable, exact resume, cancel; and brief graph
validate/materialize/children operations. The README lists exact commands and
API routes.
`task create-and-claim` accepts optional `--creation-key KEY`; ordinary task
creation does not.

## Recovery And Upgrade

Recovery uses authoritative current state, never local step files or attempt
history. After an ambiguous report, `context` and the accepted-artifact index
show whether the fenced transition occurred. An observed version, step, and
artifact prove acceptance; an unchanged matching fence permits at most one
careful retry; contradiction or unavailable observation blocks. The scheduler
does not retain artifact bytes or a pending submission.

There is no `tasks/<id>/<step>.md`, answer sidecar, inode check, pre-dispatch
deletion, rename/fsync requirement, attempt marker, step receipt, or dual-read
fallback. Old local task artifacts are not read, imported, or considered
evidence.

The execution-context migration adds accepted artifacts, pause bindings, and
answer bindings with an empty accepted-artifact map. Existing unfinished tasks
keep project and task IDs, parent and blocker relationships, task type and
immutable workflow snapshot, title and description, status, current step,
ownership data, and derived worktree. If that built-in snapshot predates
verification, the server and skills block publication: the operator preserves
work, cancels the unfinished task, and recreates it from the current catalog.
There is no automatic dual support, import, or workflow repoint. Current
snapshots may rerun their authoritative current step to reconstruct missing
accepted evidence. Rollback removes only the new execution-context columns and
preserves the pre-upgrade IDs and relationships; the migration test proves both
directions against an isolated database.

Git recovery remains observation-oriented. Publication observes the base,
candidate, and remote before retrying, never force-pushes, and never duplicates
a confirmed commit. A moved base returns to implementation or briefing as the
workflow specifies. Brief graph creation recovers by comparing the complete
observed graph and digest.

## Publication And Verification

All task changes remain uncommitted until `publish`. The publisher validates
accepted predecessor evidence and current work, fetches the default branch,
and returns the explicit backward outcome if review is invalid or the base
moved. Otherwise it stages only validated task paths, checks the staged patch,
creates one commit with subject `KOS task <id>: <title>` and exactly one
`KOS-Task: <id>` trailer, pushes without force, and confirms the candidate in
remote history. A brief publisher then materializes its validated graph. The
server will not accept `published` until those children exist, and after they
exist it permits a technical `blocked` pause but no publication outcome that
rewinds to briefing or review.

`published` advances to `verify`; it never completes the task. A fresh advanced
verification agent is read-only and independently fetches and inspects the
remote commit, trailer, changed paths, patch, expected result, and accepted
evidence without trusting publication prose or local HEAD. For a brief it also
checks the server-observed child graph. Only `verified` completes and releases
ownership; precise correction outcomes route incomplete or invalid results
backward.

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
base SHA fields, review-to-commit binding, pre-publication commits, condition
languages, parallel steps within one task, automatic conflict resolution,
force-push, automatic deletion of unknown worktrees, and Rails parsing of OKF.
