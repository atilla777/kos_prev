# Architecture Rules

These rules describe the implemented PLAN-022 state-oriented architecture.

## Boundaries

- Rails owns authoritative persistent state, validation, fencing, accepted
  artifacts, pause and answer bindings, and transactional transitions.
- The CLI is a thin authenticated HTTP client. It never reads SQLite directly
  and does not contain an agent runtime or broker.
- A slash-command orchestrator is only a scheduler: select or create, claim or
  resume, read context, dispatch one exact profile by task ID, and reread context.
- A fresh step agent owns one step: focused context reads, predecessor evidence,
  worktree operations, checks, artifact production, outcome choice, and reporting.
- The filesystem owns task worktrees and the separate pre-ID creation intent and
  receipt protocol. It does not own accepted step artifacts or human answers.
- Git owns commits and SHA values. Only the publication profile may mutate Git
  history or a remote.
- Product behavior lives in repository `specs/`; technical contracts live in
  `docs/`; accepted execution evidence lives in KOS task state.

## Design Rules

- Add mechanisms only for an end-to-end scenario and keep API projections focused.
- Enforce state invariants at the server boundary and within transactions, with
  database constraints where practical.
- Treat used workflow definitions as immutable values and keep concrete model
  identifiers in OpenCode profiles rather than workflow or task state.
- Derive machine-local worktree paths; never persist them as domain state.
- Keep external side effects outside Rails transactions and recover ambiguity by
  observing authoritative task, Git, remote, or child-graph state before retry.
- Never create a task commit before publication; never complete at publication.
- Store only the last accepted artifact per step, not attempts, pending reports,
  receipts, or a universal arbitrary state object.
- Never use local artifact fallback, dual reads, or automatic import of legacy files.

## Components

### Rails State Core

The bearer-authenticated JSON API and SQLite database own projects, workflows,
task types, tasks, dependencies, and transitions. `GET /up` remains public.
Rails validates workflow shape but has no semantic knowledge of planning,
diagnosis, checks, documentation, review, publication, verification, or OKF.

The five domain tables remain `projects`, `workflows`, `task_types`, `tasks`,
and `task_dependencies`. PLAN-022 adds execution context to `tasks`, not a new
artifact or attempt table. `accepted_artifacts` is a JSON map keyed by step ID;
each value contains `outcome`, complete `markdown`, `accepted_claim_version`,
and `reconstructed`. Pause state uses `pause_message`, `pause_step`, and
`pause_claim_version`; answer state uses `human_answer`, `human_answer_step`, and
`human_answer_claim_version`.
Request-bound tasks may also store an immutable nullable `creation_key`. A
partial unique index on project, task type, and non-null key is the final
duplicate-creation boundary; ordinary tasks remain null and unaffected.

Each report transaction validates the artifact first, resolves the workflow
action, validates a required pause message, copies and updates the accepted map,
and performs one fenced update requiring active status, owner, claim version,
current step, and unexpired lease. The update stores the artifact, applies the
transition, increments `claim_version`, and sets or clears pause and answer state.
No accepted artifact can exist without its corresponding accepted transition.
Built-in completion is additionally constrained to `verify`, regardless of an
immutable snapshot's action. Brief publication takes a SQLite write lock before
observing children, so materialization and reporting serialize; `published`
requires children, while a materialized graph forbids publication rewinds.

The artifact limit is 1 MiB by UTF-8 bytes. Artifacts must be nonempty valid
UTF-8 strings. KOS stores their exact Markdown but does not parse template
meaning. Repeating a step replaces that key; no attempt history is retained.

### CLI Transport

The packaged `kos` executable is stateless and preserves server response bodies.
Agents use only the administrator-configured absolute `KOS_CLI_PATH`. The shared
`kos-cli` skill discovers command compatibility, supplies each value as a
separate argument, validates complete JSON projections, protects credentials,
and applies operation-specific observation-before-retry rules.

The focused step interface is:

- `task context ID`, containing task execution identity, registered project,
  exact current step, artifact index, pause/answer projection, and status;
- `task artifact ID --step STEP`, containing one accepted artifact; and
- `task report-attempt ID ... --artifact-file FILE`, atomically accepting one
  artifact and transition.

`context` deliberately omits accepted Markdown from its artifact index. A step
agent separately requests only the artifacts it needs. Standard input is the
preferred report-artifact source; a compatibility temporary file must be mode
0600 in a private directory outside repositories and removed after an
unambiguous response.

### Schedulers

`skills/kos` schedules development and fix tasks; `skills/kos-brief` schedules
brief tasks. They may discover a project, offer resumable tasks, request a safe
claim or resume, and display persisted pause information. The installed
`skills/kos-create` is the sole pre-ID request-bound creation procedure for
`/kos-fix` and `/kos-brief`. It returns only a confirmed positive ID; the
scheduler does not receive its files or creation observations and then keeps
only that ID.
Each command session generates a fresh unpredictable owner for claim or resume;
`KOS_OWNER_ID` is not configuration. Request-bound creation instead retains the
owner durably generated by `kos-create`.

For each active iteration the scheduler reads `task context`, maps the exact
current built-in step to one focused profile, dispatches a fresh foreground
child whose entire prompt is the decimal task ID, ignores all returned text, and
rereads context. It never reads the task description for dispatch, workflow
Markdown, accepted artifacts, local artifacts, Git diff/status/HEAD, checks,
child outcomes, graph proposals, receipts, or pending submissions. It never
calls `report-attempt` or performs brief graph operations.

Pre-ID request creation remains distinct. `kos-create` uses the installed CLI,
a private data-home namespace keyed by project, type, and exact-request digest,
a mode-safe atomic intent, an exclusive observable lock, deterministic
server-keyed create-and-claim, and a durable request-to-task receipt. The
receipt remains the mandatory first return gate, while the server key prevents
duplicates if that file is lost. It rejects symlink
traversal and contradictory projections. Its receipt may remain as the permanent
same-request binding. It owns no step execution, artifacts, Git, graph mutation,
or workflow routing, and none of its files participates in those activities.
Before using the current namespace, it read-only recognizes the immediately
preceding `intents/<project>/<kind>-<digest>-task.json` schema and returns its
exact matching task. Unresolved legacy intents or locks block creation rather
than risking a duplicate.

### Step Agents

Every step profile loads `kos-step` and receives exactly one positive task ID.
It fetches and validates `task context`, verifies its exact built-in step and
active fence, separately fetches only required accepted predecessors, and invokes
`kos-git` with the ID. The profile, not repository prose or a parent prompt,
defines authority.

Immediately before reporting, the agent rereads context and requires the same
owner, claim version, and current step. It sends the selected allowed outcome,
complete artifact, and pause message when applicable. The server transaction is
the acceptance boundary. On an ambiguous response it observes authoritative
state through `kos-cli`; it does not create a local receipt. The child returns
only a non-authoritative confirmation and never performs a second step.

### Git And Worktrees

`kos-git` accepts only a task ID, gets the registered project and authority from
context, and derives `<kos-data-home>/worktrees/<project-id>/<task-id>`. It
requires a verified detached worktree for the registered repository and remote,
preserves staged, unstaged, and untracked work, and refuses unknown or unsafe
paths and active Git operations rather than deleting or repairing them.

Repository discovery requires one `origin` fetch URL and one push URL. Supported
HTTPS, `ssh://git@...`, and relative scp-style `git@host:...` forms normalize to
one lower-cased-host `host/namespace/repository` identity. Credentials, ports,
queries, fragments, local paths, ambiguous slashes, non-`git` SSH users, and
fetch/push identity mismatches are rejected before mutation. `kos-cli` performs
an exact registration lookup. There is no `KOS_PROJECT_*` configuration.

## Profiles And Permissions

The slash commands run in OpenCode's primary `build` agent and load scheduler
skills. Their skill access and shell authority therefore come from the user's
main-agent configuration and interactive permission policy; they are not
additional focused profile files shipped by KOS. The `.opencode/agents/kos-*`
files below govern only fresh step subagents. This boundary is intentional:
`kos-create` is callable only by the `/kos-fix` and `/kos-brief` scheduler
procedures, while focused profiles do not receive it.

The exact built-in dispatch map is:

| Step | Profile | Model role | Worktree and operation authority |
| --- | --- | --- | --- |
| `diagnose` | `kos-diagnose` | advanced | read-only KOS/Git; reproduction from an exported tree with an isolated empty environment |
| `plan` | `kos-plan` | advanced | read-only |
| `implement` | `kos-implement` | standard | edit and run checks; no commit or push |
| `document` | `kos-document` | standard | edit and use `okf`; no commit or push |
| `brief` | `kos-brief` | advanced | edit authorized specification/graph work; no commit or push |
| `review` | `kos-review` | advanced | independent and read-only |
| `publish` | `kos-publish` | standard | sole base-update, stage, commit, push, graph-validation, and materialization authority |
| `verify` | `kos-verify` | advanced | fresh independent read-only remote and result verification |

Read-only profiles deny editing and mutating Git commands. All step profiles
deny child-task dispatch, arbitrary skills, direct `kos`, `curl`, `sqlite3`, and
Rails access; they allow only `kos-step`, `kos-cli`, `kos-git`, the focused CLI
operations they need, and `okf` only for document and brief. Publish alone has
the focused children/validation/materialization operations and Git mutation.
Generic `kos-step-standard` and `kos-step-advanced` profiles handle only unknown
custom steps and may not commit or push.

These OpenCode rules are ordered command-string controls, not a complete shell
or operating-system sandbox. Unmatched shell commands ask the user; recognizable
wrapped or absolute-path direct administration and unauthorized Git mutations
are denied, and narrow `$KOS_CLI_PATH` operations are allowed last. Server
authorization and lifecycle fencing remain authoritative.

## Backward Transitions

Focused agents validate predecessor evidence and use explicit correction routes:

- Development: `plan_invalid` to `plan`, `implementation_invalid` to
  `implement`, review `changes_requested` to `implement`, `redesign_required` to
  `plan`, publish `review_invalid` to `review`, `base_moved` to `implement`,
  verify `publication_missing` to `publish`, and `changes_invalid` to `implement`.
- Fix adds plan `diagnosis_invalid` to `diagnose`; all later routes match
  development.
- Brief uses review `changes_requested` to `brief`; publish `review_invalid` to
  `review`, `base_moved` or `graph_invalid` to `brief`; and verify
  `publication_missing` or `materialization_missing` to `publish`, and
  `brief_invalid` to `brief` only before an incompatible graph exists.

Every built-in step also supports fenced `needs_human` and `blocked` pauses.
Backward execution replaces only artifacts for steps actually rerun. Later
accepted artifacts remain visible as historical last-accepted evidence, so each
step validates the exact predecessors and current repository state it relies on.

## Publication And Verification

Publication validates accepted plan, implementation, documentation, and review
evidence. A brief also validates its accepted specification and graph. If the
remote base moved, the publisher preserves task work on the new base and reports
the explicit backward outcome without committing. Otherwise it stages only
validated paths, runs `git diff --cached --check`, creates one detached commit
with one `KOS-Task: <id>` trailer, pushes without force, fetches again regardless
of push output, and reports `published` only after remote observation. Brief
children are atomically materialized only after that observation.

`published` always transitions to `verify`. A fresh verify profile performs no
checkout, index update, commit, push, graph mutation, or worktree edit. It fetches
the remote independently, locates and inspects the task commit, and compares its
paths and patch with the task and accepted evidence. Brief verification also
compares the remote specification and server-observed graph. It does not trust
the publish artifact or local HEAD. Only `verified` completes the task.

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

The PLAN-022 migration adds the artifact, pause, and answer columns with an empty
artifact map. Existing unfinished tasks preserve IDs, projects, parents,
dependencies, task types, immutable workflow snapshots, definitions, status,
current step, ownership fields, and worktrees. A built-in snapshot without the
verification route is blocked before publication side effects; preserve its
work, cancel it, and recreate it from the current catalog. It is never imported,
dual-run, or repointed. Current snapshots may rerun their current step to
reconstruct missing evidence; legacy local files remain ignored. The isolated
migration test migrates up, verifies preservation and empty artifacts, migrates
down, verifies only new columns disappear, and rechecks IDs and relationships.

Creation intents and receipts remain pre-ID files, but scoped server creation
keys are the final duplicate defense when a receipt is lost. Git publication
and brief materialization ambiguity are recovered from remote Git and complete
server graph observations respectively, never from step receipts.

See [the system specification](specification.md), [testing rules](testing.md),
and [installation guide](installation.md).
