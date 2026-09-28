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

Start Rails for local use, configure the CLI, and verify liveness:

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
Use `workflow list` to discover available keys and revision IDs, `workflow show
ID` to inspect one revision, and `workflow schema` to print the authoritative
definition contract and complete example. Per-command help identifies required
arguments, input and response shapes, examples, and exact file or standard-input
options.
The service rejects JSON request bodies over 8 MiB; coordination field, graph,
and result limits are documented in the
[product specification](specification.md#coordination-limits).

## Register A Project

Registration is an explicit administrator step before the first `/kos` run. KOS
requires a supported Git remote URL and a chosen default branch as durable
metadata. It does not create a local repository, GitHub repository, initial
commit, branch, clone, or worktree, and it does not check remote reachability.

Create the remote repository first and use an existing checkout for OpenCode.
If a worker will clone the remote or create a worktree from its default branch,
publish at least one commit on that branch first. KOS registration itself does
not require the branch to be reachable and does not perform this Git check.

For example, register an existing private GitHub repository:

```sh
"$KOS_CLI_PATH" project create \
  --name "Widget" \
  --remote-url "git@github.com:acme/widget.git" \
  --default-branch "main"
```

The response contains the numeric `id` used by project-scoped plan and task
commands and the canonical `repository_identity` used for lookup:

```json
{
  "project": {
    "id": 1,
    "name": "Widget",
    "repository_identity": "github.com/acme/widget",
    "remote_url": "git@github.com:acme/widget.git",
    "default_branch": "main"
  }
}
```

The server derives the identity when `--repository-identity` is omitted. Its
canonical form includes the lowercased host and repository path, strips a final
`.git`, and preserves path case. From the intended checkout, explicitly select
the remote used for recovery and verify registration before invoking `/kos`:

```sh
"$KOS_CLI_PATH" project resolve --remote origin
"$KOS_CLI_PATH" status --remote origin
```

An HTTP 404 with `error: not_found` means no project is registered under that
exact identity; it is not a request to create one. Recheck the host-qualified
identity or run `project create`. Local paths and `file://` remotes are not
stable repository identities and cannot be registered.

These commands inspect only the selected local remote URL. They do not choose a
remote, fetch, test reachability, or change Git or KOS state. `status` returns
the project plus its non-completed plans and tasks for recovery.

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
with the project ID returned by the registration step above:

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

An explicit `--config-home` must be absolute and is rejected before any file is
changed otherwise. Without that option, an absolute nonempty `XDG_CONFIG_HOME`
selects `$XDG_CONFIG_HOME/opencode`; a relative or empty value is ignored and
the installer uses `$HOME/.config/opencode`.

The installer manages exactly:

- command `kos.md`, exposed as `/kos`;
- agent `kos-worker.md`; and
- skills `kos`, `kos-cli`, `kos-worker`, and `okf`.

The successful-install marker is `kos-installation.json`. On update, the
installer validates the prior marker and removes assets owned by its inventory
but absent from the new release. With no marker, it removes only the finite
historical KOS command, agent, and skill names reserved by pre-manifest
releases, including current names that existed in those integrations. Those
`kos*` and `okf` paths are reserved for this one-time migration; every unrelated
name is preserved. With a valid marker, an existing current destination not
owned by that marker is rejected rather than overwritten. A malformed,
unsupported, symlinked, or non-KOS inventory marker stops installation before
any file changes; inspect it and reinstall rather than trusting a partial or
unknown inventory.

Fully restart OpenCode after installation or any managed-file change; a running
process can retain already loaded commands, agents, and skills. Then verify the
manifest, packaged CLI, server identity, and server readiness before `/kos`:

```sh
"$KOS_CLI_PATH" installation check
```

The command locates the default manifest through `XDG_CONFIG_HOME` or
`$HOME/.config/opencode`. For a custom destination, pass `--manifest` with an
absolute path or set `KOS_OPENCODE_MANIFEST`. A missing, invalid, stale, or
mismatched manifest fails with reinstall guidance. A matching server that has
pending migrations, a stale catalog, or unavailable storage fails separately as
`not_ready`.

The `/kos`
agent coordinates only: it discovers non-completed state before creating work,
discovers and selects existing workflows, stores plans, finds and claims ready
work, dispatches workers, presents pauses, performs explicit takeover or exact
release of a known cancelled dispatch, abandons started plans only with explicit
user intent, and observes state. A planning-only
request stops after plan storage, before ready discovery or dispatch. An absent
explicitly requested workflow requires a question rather than a guessed key or
fallback definition. Each `kos-worker` performs and reports one current step.
Cancelling that runtime worker does not clear its KOS claim; reread the task
before releasing its exact envelope or taking it over. Release returns the same
step to pending without a replacement; takeover installs one immediately. The
managed command and agent inherit the model and provider
selected by OpenCode; configure and authenticate a provider before the first
run.

## Production

Run one supervised Rails/Puma process on the same host as SQLite, bound to
loopback behind a TLS reverse proxy. Do not set `WEB_CONCURRENCY`; the supported
deployment has one Puma process. Do not place SQLite on a network or synchronized
filesystem.

Create a dedicated account and storage owned only by that account. Keep the
release checkout root-owned and readable and executable, but not writable, by
the service account:

```sh
useradd --system --home-dir /var/lib/kos --shell /usr/sbin/nologin kos
install -d -o kos -g kos -m 0700 /var/lib/kos /var/lib/kos/backups
install -d -o root -g kos -m 0750 /etc/kos
install -o root -g kos -m 0640 /dev/null /etc/kos/kos.env
```

Store at least these values in `/etc/kos/kos.env`:

```dotenv
RAILS_ENV=production
KOS_DATA_HOME=/var/lib/kos
KOS_API_TOKEN=<installation-token>
SECRET_KEY_BASE=<openssl-rand-hex-64-output>
BIND=127.0.0.1
PORT=3000
```

Prepare and seed from the release checkout as the service account so it owns the
database and SQLite sidecar files. The supervisor starts the same Rails command:

```sh
sudo -u kos sh -c '
  set -a
  . /etc/kos/kos.env
  set +a
  bin/rails db:prepare
  bin/rails db:seed
'
```

For example, a systemd unit may use:

```ini
[Unit]
Description=KOS
After=network.target

[Service]
User=kos
Group=kos
WorkingDirectory=/opt/kos/current
EnvironmentFile=/etc/kos/kos.env
ExecStart=/opt/kos/current/bin/rails server
Restart=on-failure
UMask=0077

[Install]
WantedBy=multi-user.target
```

The TLS reverse proxy must send traffic only to `127.0.0.1:3000`, overwrite
client-supplied forwarding headers, set `X-Forwarded-Proto: https`, preserve
`Host` and `Authorization`, and omit authorization values from logs. `GET /up`
is public process liveness. `GET /ready` is public dependency readiness and
checks database access and writability, migrations, the built-in catalog, and
the data directory. A `503` response means the process is alive but must not
receive application traffic. Every other route requires the bearer token.

Probe both endpoints through the proxy:

```sh
curl --fail --silent --show-error https://kos.example/up >/dev/null
curl --fail --silent --show-error https://kos.example/ready
```

## Backup

The database contains all KOS coordination state. First stop OpenCode
orchestrators and workers, then stop the service so no application writer is
active. Record the deployed tag or commit with each backup:

```sh
set -eu
systemctl stop kos
KOS_DATA_HOME=/var/lib/kos
release_checkout=/opt/kos/current
mkdir -p "$KOS_DATA_HOME/backups"
backup="$KOS_DATA_HOME/backups/production-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
sqlite3 "$KOS_DATA_HOME/production.sqlite3" ".backup '$backup'"
test "$(sqlite3 "$backup" "PRAGMA integrity_check;")" = ok
test -z "$(sqlite3 "$backup" "PRAGMA foreign_key_check;")"
git -C "$release_checkout" rev-parse HEAD >"$backup.commit"
chmod 0600 "$backup" "$backup.commit"
systemctl start kos
curl --fail --silent --show-error https://kos.example/ready
```

Require `integrity_check` to return `ok` and `foreign_key_check` to return no
rows. A backup preserves old state for reference or rollback to the matching old
release; it is not imported into the new agent-led schema.

## Restore

Restore only with the matching application/schema release unless compatibility
has been explicitly verified. Stop every client and the service, verify the
backup again, remove stale SQLite sidecar files, and install the database with
service ownership:

```sh
set -eu
systemctl stop kos
KOS_DATA_HOME=/var/lib/kos
release_checkout=/opt/kos/current
backup=/var/lib/kos/backups/production-YYYYMMDDTHHMMSSZ.sqlite3
test "$(git -C "$release_checkout" rev-parse HEAD)" = "$(cat "$backup.commit")"
test "$(sqlite3 "$backup" "PRAGMA integrity_check;")" = ok
test -z "$(sqlite3 "$backup" "PRAGMA foreign_key_check;")"
rm -f "$KOS_DATA_HOME/production.sqlite3-wal" \
  "$KOS_DATA_HOME/production.sqlite3-shm" \
  "$KOS_DATA_HOME/production.sqlite3-journal"
install -o kos -g kos -m 0600 "$backup" "$KOS_DATA_HOME/production.sqlite3.restore"
mv "$KOS_DATA_HOME/production.sqlite3.restore" "$KOS_DATA_HOME/production.sqlite3"
systemctl start kos
curl --fail --silent --show-error https://kos.example/up >/dev/null
curl --fail --silent --show-error https://kos.example/ready
set -a
. /etc/kos/kos.env
set +a
export KOS_API_URL=https://kos.example
KOS_CLI_PATH="$(command -v kos)"
"$KOS_CLI_PATH" project show --repository-identity github.com/OWNER/REPOSITORY
"$KOS_CLI_PATH" plan list --project-id ID
"$KOS_CLI_PATH" task list --project-id ID
```

The public probes do not validate the bearer token, so the authenticated reads
are required.

## Credential Rotation

KOS accepts one shared bearer token and does not overlap old and new tokens.
Pause new dispatches and stop OpenCode processes that may submit the old token.
From a root shell, atomically replace the service token, restart the service,
and retain both values only long enough to verify the rotation:

```sh
set -eu
set -a
. /etc/kos/kos.env
set +a
old_token="$KOS_API_TOKEN"
new_token="$(openssl rand -hex 32)"
cp --preserve=mode,ownership /etc/kos/kos.env /etc/kos/kos.env.new
sed -i "s/^KOS_API_TOKEN=.*/KOS_API_TOKEN=$new_token/" /etc/kos/kos.env.new
mv /etc/kos/kos.env.new /etc/kos/kos.env
systemctl restart kos
curl --fail --silent --show-error https://kos.example/ready
test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: Bearer $old_token" \
  'https://kos.example/projects?repository_identity=github.com%2FOWNER%2FREPOSITORY')" = 401
export KOS_API_TOKEN="$new_token"
export KOS_API_URL=https://kos.example
KOS_CLI_PATH="$(command -v kos)"
"$KOS_CLI_PATH" project show --repository-identity github.com/OWNER/REPOSITORY
unset old_token new_token
```

Update `KOS_API_TOKEN` in every CLI and OpenCode execution environment before
resuming orchestration. Rotation does not release task claims; after rereading
authoritative state, release only an exact known stopped dispatch when no
immediate replacement is wanted, or take it over when replacement is intended.

## Pre-Release Upgrade

Upgrading from PLAN-022 is destructive. KOS provides no legacy migration,
dual-read path, or automatic import for task types, tasks, leases, artifacts,
request keys, or brief graphs.

1. Stop Rails, OpenCode, and every orchestrator or worker.
2. Optionally create and verify a backup of the old SQLite database.
3. Remove the old `production.sqlite3` and its SQLite `-wal` and `-shm` files.
4. Install the new release and, from its checkout, run database preparation as
   the service account:
   ```sh
   sudo -u kos sh -c '
     set -a
     . /etc/kos/kos.env
     set +a
     bin/rails db:prepare
     bin/rails db:seed
   '
   ```
5. Reinstall the CLI and run `bin/install-opencode` from that same release.
6. Recreate projects with `project create`.
7. Recreate custom workflows with `workflow create`; seeding installs the
   built-in workflows.
8. Recreate current task plans and dependencies with `plan put`.
9. Restart Rails and OpenCode, then verify `health` and the corresponding `show`
   commands.

Do not restore the old database into the new release. Treat the checkout, CLI,
OpenCode inventory, and database as one rollback unit. With all clients stopped,
use the tag or commit recorded beside the backup and an absolute OpenCode
configuration path:

```sh
set -eu
systemctl stop kos
old_release=v0.1.0-pre.N
backup=/var/lib/kos/backups/production-YYYYMMDDTHHMMSSZ.sqlite3
release_checkout=/opt/kos/current
OPENCODE_CONFIG_HOME=/home/USER/.config/opencode
opencode_user=USER
git -C "$release_checkout" fetch --tags
git -C "$release_checkout" checkout "$old_release"
test "$(git -C "$release_checkout" rev-parse HEAD)" = "$(cat "$backup.commit")"
test "$(sqlite3 "$backup" "PRAGMA integrity_check;")" = ok
test -z "$(sqlite3 "$backup" "PRAGMA foreign_key_check;")"
rm -f /var/lib/kos/production.sqlite3-wal \
  /var/lib/kos/production.sqlite3-shm \
  /var/lib/kos/production.sqlite3-journal
install -o kos -g kos -m 0600 "$backup" /var/lib/kos/production.sqlite3.restore
mv /var/lib/kos/production.sqlite3.restore /var/lib/kos/production.sqlite3
gem build -C "$release_checkout" kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
sudo -u "$opencode_user" "$release_checkout/bin/install-opencode" \
  --config-home "$OPENCODE_CONFIG_HOME"
systemctl start kos
curl --fail --silent --show-error https://kos.example/up >/dev/null
curl --fail --silent --show-error https://kos.example/ready
set -a
. /etc/kos/kos.env
set +a
export KOS_API_URL=https://kos.example
KOS_CLI_PATH="$(command -v kos)"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" project show --repository-identity github.com/OWNER/REPOSITORY
```

Never combine one release's database with arbitrary application or integration
assets from another release.

## Pre-Release Verification

Use immutable annotated tags of the form `v<VERSION>-pre.<N>`, where `VERSION`
equals `Kos::VERSION`; never move or reuse a tag. From a clean committed candidate
that is already pushed, run the deterministic gates:

```sh
bin/check
ruby tasks/031-prove-installed-orchestration/artifacts/verify_evidence.rb
```

The task 031 verifier validates retained evidence from its recorded candidate;
it does not claim a new live-model run for the current release. New live-model
exercises remain optional.

Build and install the gem and OpenCode inventory from the candidate. Require the
source identity printed by `kos --version`, returned by `GET /ready`, and stored
in `kos-installation.json` to match. Then create and publish the tag without
force:

```sh
tag=v0.1.0-pre.1
test -z "$(git status --porcelain)"
git tag -a "$tag" -m "KOS $tag"
test "$(git rev-parse HEAD)" = "$(git rev-parse "$tag^{}")"
git push origin "$tag"
git ls-remote --exit-code origin "refs/tags/$tag^{}"
```

Observe the remote `Check` workflow and require it to pass for the tagged commit.
Release verification is complete only after the remote tag resolves to the
intended commit and remote CI succeeds.
