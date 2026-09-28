# Installation

Install the Rails service, CLI gem, and OpenCode integration from one release
revision.

## Prerequisites

- Ruby 3.4.10 and Bundler 4.0.20
- SQLite 3 with development headers and the `sqlite3` program
- OpenCode 1.18.26 or later

## Server And CLI

```sh
git fetch --tags
git checkout <release-tag-or-commit>
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare
bin/rails db:seed

gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" --help
```

`KOS_DATA_HOME` must be an absolute path on local storage. Keep
`KOS_API_TOKEN` secret; it authorizes all application operations for this
trusted single-installation MVP.

Start Rails, configure the CLI, and verify liveness:

```sh
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails server
"$KOS_CLI_PATH" health
```

Use `project create`, `workflow create`, and `plan put` to create the durable
state needed by `/kos`. Use `project show`, `plan list`, and `task list` to
recover non-completed state after a restart; use `plan show` for one detailed plan.
The list commands include terminal abandoned state but exclude completed state
unless `--include-completed` is given. Use `plan abandon` only with explicit
intent to retire erroneous or obsolete started work, passing the current plan
version from `plan show` or `plan list`. It does not undo external effects.
Consult per-command help for exact file and standard-input options.

For a minimal first run, save this one-step workflow as `workflow.json`:

```json
{
  "steps": [
    {
      "id": "work",
      "name": "Work",
      "instruction": "Perform the task description and report the observed result.",
      "outcomes": {
        "completed": { "complete_task": true },
        "question": { "pause": "needs_human" },
        "blocked": { "pause": "blocked" }
      }
    }
  ]
}
```

Register it, then save a two-task plan as `plan.json` and store it. Replace `1`
with the project ID returned by `project create`:

```sh
"$KOS_CLI_PATH" workflow create --key first-run --name "First run" \
  --definition-file workflow.json
```

```json
{
  "key": "first-run",
  "title": "First KOS plan",
  "tasks": [
    {
      "key": "first",
      "title": "First independent task",
      "description_markdown": "Create `first.txt` containing `first`.",
      "workflow_key": "first-run",
      "blocker_keys": []
    },
    {
      "key": "second",
      "title": "Second independent task",
      "description_markdown": "Create `second.txt` containing `second`.",
      "workflow_key": "first-run",
      "blocker_keys": []
    }
  ]
}
```

```sh
"$KOS_CLI_PATH" plan put --project-id 1 --definition-file plan.json
```

Run `bin/rails db:seed` after each KOS upgrade. Seeding idempotently installs the
current built-in catalog revision while preserving obsolete workflow revisions
used by existing tasks.

## OpenCode Inventory

```sh
bin/install-opencode
```

The installer manages exactly:

- command `kos.md`, exposed as `/kos`;
- agent `kos-worker.md`; and
- skills `kos`, `kos-cli`, `kos-worker`, and `okf`.

Restart OpenCode after installation or any managed-file change. The `/kos`
agent coordinates only: it discovers non-completed state before creating work,
stores plans, finds and claims ready work, dispatches workers, presents pauses,
performs explicit takeover, abandons started plans only with explicit user
intent, and observes state. Each `kos-worker` performs and reports one current
step. The managed command and agent inherit the model and provider selected by
OpenCode; configure and authenticate a provider before the first run.

## Production

Run one supervised Rails/Puma process on the same host as SQLite, bound to
loopback behind a TLS reverse proxy. Do not place SQLite on a network or
synchronized filesystem. Supply at least these environment values to the
service:

```dotenv
KOS_DATA_HOME=/var/lib/kos
KOS_API_TOKEN=<installation-token>
SECRET_KEY_BASE=<openssl-rand-hex-64-output>
```

`GET /up` is public process liveness. Restrict all application routes through
the bearer token, and ensure proxy logs omit `Authorization` headers.

## Backup

The database contains all KOS coordination state. Stop clients and application
writers before taking a consistent SQLite backup:

```sh
mkdir -p "$KOS_DATA_HOME/backups"
backup="$KOS_DATA_HOME/backups/production-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
sqlite3 "$KOS_DATA_HOME/production.sqlite3" ".backup '$backup'"
sqlite3 "$backup" "PRAGMA integrity_check; PRAGMA foreign_key_check;"
```

Require `integrity_check` to return `ok` and `foreign_key_check` to return no
rows. A backup preserves old state for reference or rollback to the matching old
release; it is not imported into the new agent-led schema.

## Pre-Release Upgrade

Upgrading from PLAN-022 is destructive. KOS provides no legacy migration,
dual-read path, or automatic import for task types, tasks, leases, artifacts,
request keys, or brief graphs.

1. Stop Rails, OpenCode, and every orchestrator or worker.
2. Optionally create and verify a backup of the old SQLite database.
3. Remove the old `production.sqlite3` and its SQLite `-wal` and `-shm` files.
4. Install the new release and run `RAILS_ENV=production bin/rails db:prepare`
   followed by `RAILS_ENV=production bin/rails db:seed`.
5. Reinstall the CLI and run `bin/install-opencode` from that same release.
6. Recreate projects with `project create`.
7. Recreate custom workflows with `workflow create`; seeding installs the
   built-in workflows.
8. Recreate current task plans and dependencies with `plan put`.
9. Restart Rails and OpenCode, then verify `health` and the corresponding `show`
   commands.

Do not restore the old database into the new release. Rollback means stopping
the new release and using the verified old database only with its matching old
application and integration assets.

## Check

Run `bin/check` in the release checkout. It is the complete automated acceptance
contract for storage, API, CLI, concurrency, persistence, and installed assets.
Live-model workflow runs are optional operational exercises, not release gates.
