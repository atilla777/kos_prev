# KOS

KOS is a small authoritative store for coordinating capable AI agents. It keeps
projects, immutable workflow revisions, task plans, dependencies, task state,
claims, pauses, answers, and the latest accepted result for each executed step.
It does not perform or judge diagnosis, implementation, testing, review, Git, or
publication.

The main orchestrator maintains a plan, selects dependency-ready tasks, claims
them, dispatches workers, presents pauses, performs explicit takeover, and
observes state. Every worker performs exactly one current workflow step and
reports one allowed outcome. Independent tasks may run in parallel; one task has
at most one current worker.

`/kos` is the sole orchestration command. It discovers existing workflows and
uses `development` for implementation, `fix` for defect correction, `brief` for
specification work, or an explicitly requested custom workflow. Planning-only
goals stop after atomic plan storage, before ready discovery or worker dispatch.

## Coordination Model

- A plan stores all of its tasks and dependencies atomically. It may be replaced
  only before any task in it starts.
- A started plan may be abandoned with explicit intent and its observed plan
  version. All unfinished tasks become terminal while completed results remain.
- A task is ready when it is pending and all blockers are complete.
- A claim has an unpredictable `claim_id`, belongs to one worker dispatch, and
  does not expire. There are no leases, heartbeats, or clock-based recovery.
- Every task has an optimistic `version`. Claim, takeover, answer, and report
  operations reject stale versions; reports also reject stale claims or steps.
- Explicit takeover installs a new claim and invalidates the previous worker.
- Cancelling an OpenCode worker does not change KOS state; reread the task before
  deciding whether its active claim should be taken over.
- An accepted report stores the latest result for the executed step and applies
  its declared workflow transition in one transaction.
- Pause questions and technical obstructions are durable. An answer remains
  bound to the paused step until that step reports successfully.
- Built-in and custom workflows use the same transition rules. Names such as
  `review` or `publish` have no special server behavior.

KOS state, not agent prose, is authoritative. A worker reports its own result
and never continues to the next step.

## Install

Prerequisites are Ruby 3.4.10, Bundler 4.0.20, SQLite 3, and OpenCode 1.18.26 or
later.

```sh
gem install bundler --version 4.0.20
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare
bin/rails db:seed

gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"

bin/install-opencode
```

Fully restart OpenCode after installation, then verify that the OpenCode
manifest, CLI, and ready server came from the same source revision:

```sh
kos installation check
```

This pre-release architecture is intentionally incompatible with PLAN-022
databases. Upgrading requires stopping KOS, optionally backing up the old SQLite
file, deleting it, preparing a new database, and recreating projects, workflows,
and plans. KOS does not migrate legacy tasks or artifacts. See
[Installation](docs/installation.md).

The OpenCode installer manages exactly:

- command `/kos`;
- agent `kos-worker`; and
- skills `kos`, `kos-cli`, `kos-worker`, and `okf`.

## CLI

Configure the client with `KOS_API_URL` and `KOS_API_TOKEN`. `kos health` uses
the public liveness endpoint and does not require the token. The public command
surface is:

```text
kos health
kos claim-id
kos installation check
kos project create|show|update
kos workflow create|list|show|schema
kos plan put|list|show|abandon
kos task list|ready|show|context|result|claim|takeover|report|answer
```

`claim-id` creates a local unpredictable identity for one worker dispatch.
`installation check` validates the successful OpenCode installation manifest
and requires its version and `source_id` to match both the CLI and `/ready`.
`workflow list` discovers keys and immutable revision IDs, `workflow show ID`
reads one revision, and `workflow schema` prints the authoritative definition
contract with a complete valid example. `workflow create --help` includes the
same exact shape and example. `project`, `workflow`, and `plan` commands
administer durable definitions.
`plan list` and `task list` discover non-completed project state after
interruption, including terminal abandoned records; `--include-completed` adds
successful history for deliberate inspection. `task
ready` supports orchestrator scheduling; `show` observes lifecycle state;
`context` gives one worker its task, project, current instruction, outcomes,
pause/answer, and result index; `result` returns one latest accepted step result.
The remaining task commands are version-fenced mutations.

Use `kos --help` and per-command help for required arguments, accepted
identifiers, input shapes, response fields, and examples. Prefer standard input
or file options for workflow definitions, plans, results, questions, and answers
rather than interpolating structured content into shell commands.

Register a project once before using `/kos`:

```sh
kos project create \
  --name "Widget" \
  --remote-url "git@github.com:acme/widget.git" \
  --default-branch "main"
kos project show --repository-identity "github.com/acme/widget"
```

Use the `id` and canonical `repository_identity` returned by `project create`.
The remote repository and selected default branch must already exist and be
published when workers need to clone or create worktrees. KOS does not create
GitHub repositories, initial commits, branches, clones, or worktrees; run
OpenCode in the intended existing checkout. See the complete bootstrap in
[Installation](docs/installation.md#register-a-project).

## API

The JSON API exposes public probes and authenticated coordination operations:

```text
GET  /up
GET  /ready
POST /projects
GET  /projects?repository_identity=IDENTITY
PATCH /projects/:id
POST /workflows
GET  /workflows[?key=KEY]
GET  /workflows/schema
GET  /workflows/:id
PUT  /projects/:project_id/plan
GET  /projects/:project_id/plan?key=KEY
POST /projects/:project_id/plan/abandon
GET  /projects/:project_id/plans[?include_completed=true]
GET  /projects/:project_id/tasks[?include_completed=true]
GET  /tasks/ready?project_id=ID
GET  /tasks/:id
GET  /tasks/:id/context
GET  /tasks/:id/result?step=STEP
POST /tasks/:id/claim
POST /tasks/:id/takeover
POST /tasks/:id/report
POST /tasks/:id/answer
```

`GET /up` reports process liveness. `GET /ready` returns `200` only when the
database, migrations, built-in catalog, and data directory are ready, and
returns `503` otherwise. These two probes are public; every coordination route
requires the bearer token.

Definition writes validate completely before changing state. Lifecycle writes
are atomic and return conflicts for stale `version`, `claim_id`, or step data.
Plan abandonment is atomic, version-fenced, and does not roll back external
effects. Known validation, absence, and conflict failures use stable JSON errors.
Missing-resource errors retain `error: not_found` and identify the resource and
lookup value.

## Verify

```sh
bin/check
```

`bin/check` is the repository acceptance command. It covers the production
storage, API, CLI, workflow, concurrency, persistence, and installation
contracts; live-model runs are not a release gate.

## Documentation

- [Product specification](specs/kos.md)
- [System specification](docs/specification.md)
- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
- [Installation](docs/installation.md)
- [Contributing](CONTRIBUTING.md)
