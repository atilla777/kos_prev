# Installation

Install the Rails service, CLI gem, built-in catalog, and OpenCode integration
from one checked-out Git revision. Mixed revisions are unsupported because step
context, artifact reporting, profiles, and workflow outcomes are one protocol.

## Prerequisites

- Ruby 3.4.10 and Bundler 4.0.20;
- SQLite 3 with development headers and the `sqlite3` command-line program;
- Git; and
- OpenCode 1.18.26 or later with credentials for the configured models.

## Server And CLI

Check out the release, configure a local persistent data home and bearer token,
install dependencies, and prepare the database:

```sh
git fetch --tags
git checkout <release-tag-or-commit>
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="$(openssl rand -hex 32)"
bundle check || bundle install
bin/rails db:prepare
bin/rails db:seed
```

`KOS_DATA_HOME` must be an absolute local path outside the checkout, not a
synchronized or network-mounted directory. Database preparation installs the
canonical `brief`, `development`, and `fix` task types and workflows. Explicit
seeding is required because an existing prepared database does not rerun seeds
automatically. Neither command registers a project.

Build and install the exact CLI revision outside the checkout, then retain its
absolute path:

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" --version
"$KOS_CLI_PATH" --help
"$KOS_CLI_PATH" session-id
```

## OpenCode Inventory

Install the managed integration from the same checkout:

```sh
bin/install-opencode
```

The default destination is `$XDG_CONFIG_HOME/opencode`, or
`~/.config/opencode`. `--config-home <absolute-path>` selects an isolated or
nonstandard destination. The installer copies this exact inventory:

- commands: `kos.md`, `kos-fix.md`, `kos-brief.md`, and `kos-task.md`;
- generic step agents: `kos-step-standard.md` and `kos-step-advanced.md`; and
- skills: `kos`, `kos-cli`, `kos-step`, `kos-git`,
  and `okf`.

It also writes `$CONFIG_HOME/kos-installation.json` as the final successful
installation marker. Its `source_id` is the SHA-256 identity of the operational
source payload used by the server, CLI package, and installer.

The installer removes obsolete role-specific KOS agent profiles, including
`kos-brief.md`, `kos-diagnose.md`, `kos-document.md`, `kos-implement.md`,
`kos-plan.md`, `kos-publish.md`, and `kos-review.md`, plus the obsolete
`kos-brief` skill and earlier managed profiles. It refuses symlinked or wrongly typed managed
destinations.
Slash commands run in the primary `build` agent under the user's main-agent permission
policy; generic profiles apply only after ID-only subagent dispatch.
Managed profiles contain no KOS-specific permission blocks: they select a
model, reasoning effort, and prompt, while tool approval remains part of the
administrator's OpenCode configuration.

The shipped generic standard profile uses `openai/gpt-5.6-terra` with medium
reasoning, and the generic advanced profile uses `openai/gpt-5.6-sol` with high
reasoning. `/kos` and `/kos-fix` use Terra; `/kos-brief` and `/kos-task` use Sol.
The custom command therefore executes every custom `main` step in its fixed
advanced command agent; step tiers select models only for subagents.
Administrators may substitute
complete `provider/model-id` values while preserving the two tiers.
Check availability with `opencode models openai`.

Restart OpenCode after every installation or profile, command, skill, or model
change. A running OpenCode process does not reload this inventory.

## Production Service

The supported topology is one Puma process on the same host as SQLite and
OpenCode, supervised by systemd and bound to loopback. A separately supervised
TLS reverse proxy is the only public listener. The proxy owns certificates,
renewal, redirects, and public access logs; it forwards to `127.0.0.1:3000` and
must not log `Authorization` values. Public Puma listeners, multi-host service,
and network filesystems are unsupported.

Provision the service account and persistent directory, then create a root-owned,
group-readable `0640` `/etc/kos/kos.env`:

```sh
sudo useradd --system --home /var/lib/kos --shell /usr/sbin/nologin kos
sudo install -d -o kos -g kos -m 0750 /var/lib/kos
sudo install -d -o root -g kos -m 0750 /etc/kos
sudo install -o root -g kos -m 0640 /dev/null /etc/kos/kos.env
sudoedit /etc/kos/kos.env
```

Enter these assignments in that file; they are not shell commands:

```dotenv
KOS_DATA_HOME=/var/lib/kos
KOS_API_TOKEN=<installation-token>
SECRET_KEY_BASE=<openssl-rand-hex-64-output>
RAILS_MAX_THREADS=3
```

Install `/etc/systemd/system/kos.service`, replacing the user and release path:

```ini
[Unit]
Description=KOS task coordination service
After=network.target

[Service]
Type=simple
User=kos
Group=kos
WorkingDirectory=/opt/kos/releases/<source-revision>
Environment=RAILS_ENV=production
Environment=BIND=127.0.0.1
Environment=PORT=3000
EnvironmentFile=/etc/kos/kos.env
ExecStart=/usr/bin/env bundle exec puma -C config/puma.rb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Puma defaults to loopback; do not override `BIND` with a public address. From
the release directory, prepare production state as the service user with the
same environment before enabling the service:

```sh
sudo -u kos sh -c 'set -a; . /etc/kos/kos.env; set +a; RAILS_ENV=production bin/rails db:prepare'
sudo -u kos sh -c 'set -a; . /etc/kos/kos.env; set +a; RAILS_ENV=production bin/rails db:seed'
sudo systemctl daemon-reload
sudo systemctl enable --now kos.service
```

Run Caddy as the separately supervised proxy. A minimal site block is:

```caddyfile
kos.example.test {
  @ready {
    path /ready
    remote_ip 127.0.0.1/32 10.0.0.0/8
  }
  handle @ready {
    reverse_proxy 127.0.0.1:3000
  }
  handle /ready {
    respond 404
  }
  handle {
    reverse_proxy 127.0.0.1:3000
  }
}
```

Caddy owns certificate acquisition and renewal. Its default access log does not
record request headers; any customized log format must continue to omit
`Authorization`. Replace the example private range with the monitoring network,
do not expose `/ready` to untrusted clients, and probe it no more than once every
10 seconds because it deliberately verifies a SQLite writer transaction and
durable data-home write. Reload Caddy only after validating its configuration.

The reverse proxy sends the original HTTPS scheme. Production uses
`assume_ssl`; direct loopback HTTP is a trusted backend path, not the public TLS
boundary. `GET /up` is unauthenticated liveness: Rails booted and can answer.
`GET /ready` is unauthenticated readiness: the database is queryable, migrations
are current, the canonical catalog is installed, and the data home accepts a
durable temporary write. Failure returns generic `503` JSON and logs only the
failed component and exception class with the request ID.

Verify the public service and common provenance:

```sh
curl --fail https://kos.example.test/up
curl --fail http://127.0.0.1:3000/ready
"$KOS_CLI_PATH" --version
cat "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/kos-installation.json"
```

The `/ready` `source_id`, CLI `source=...`, and manifest `source_id` must match.
A mismatch is a mixed installation and is not ready for task execution.

## Configure And Register

Expose the same data home, installed CLI, token, and public API URL to OpenCode,
then explicitly register each repository:

```sh
export KOS_DATA_HOME="/var/lib/kos"
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="https://kos.example.test"
export KOS_CLI_PATH="$(realpath "$(command -v kos)")"
"$KOS_CLI_PATH" health
"$KOS_CLI_PATH" project create \
  --name "My project" \
  --remote-url "https://github.com/example/my-project.git" \
  --repository-identity "github.com/example/my-project" \
  --default-branch "main"
"$KOS_CLI_PATH" project show \
  --repository-identity "github.com/example/my-project"
```

The process that starts OpenCode must inherit the same absolute
`KOS_DATA_HOME` as Rails. `kos-git` derives every task checkout as
`$KOS_DATA_HOME/worktrees/<project-id>/<task-id>` and refuses a missing or
relative value. The installer copies integration assets but does not persist
the launch environment. Rails and OpenCode may run as separate processes on
the same host, but their configured data-home paths must identify the same
local directory.

`health` calls public liveness and does not require a token; use `/ready` for
deployment admission. `session-id` is entirely local and requires neither API
setting. All other CLI operations use the same `KOS_API_URL` and require the
`KOS_API_TOKEN` configured when Rails started. Tokens must be valid UTF-8,
nonempty, free of HTTP control characters, and have no surrounding whitespace.
This shared bearer token
trusts its holders for every application operation. Owner IDs, leases, and
claim-version fences coordinate concurrent trusted operations; they do not
provide per-agent authorization.

The registration identity must exactly match the canonical identity derived
from the invoking checkout's single `origin` fetch and push URLs. Equivalent
supported SSH and HTTPS URLs normalize to the same identity. A missing,
ambiguous, malformed, or mismatched origin blocks before task or worktree
mutation. There are no `KOS_PROJECT_*` environment variables.

After restarting OpenCode, verify discovery of `/kos-brief`, `/kos`, `/kos-fix`,
and `/kos-task`. The custom command selects an existing task by exact stable
custom task-type key; it never creates work and rejects the three reserved
built-in keys. CLI help remains the fallback syntax reference for uncommon
operations and compatibility diagnosis. Verify the installed focused operations directly:

```sh
"$KOS_CLI_PATH" task context --help
"$KOS_CLI_PATH" task artifact --help
"$KOS_CLI_PATH" task report-attempt --help
```

The installation is not ready until those operations, including report artifact
input, and all managed profiles and skills come from the same revision.

## Backup And Restore

The database owns task state; worktrees and source repositories own unpublished
commits and Git objects. A database backup alone is not a backup of active work,
and copying linked worktree directories is not a portable Git backup.

Stop every scheduler and OpenCode process, then stop Puma gracefully. Keep
project repositories and `$KOS_DATA_HOME/worktrees` unchanged until the backup
or upgrade decision is complete:

```sh
sudo systemctl stop kos.service
sudo -u kos sh -c '
  set -eu
  set -a; . /etc/kos/kos.env; set +a
  mkdir -p "$KOS_DATA_HOME/backups"
  backup="$KOS_DATA_HOME/backups/production-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
  sqlite3 "$KOS_DATA_HOME/production.sqlite3" ".backup '\''$backup'\''"
  sqlite3 "$backup" "PRAGMA integrity_check; PRAGMA foreign_key_check;"
'
```

Require exactly one `ok` line and no additional output. Never copy a live main
database file directly; journal or WAL state can make it inconsistent. Back up
source repositories with normal Git repository tooling.

Rehearse restore before relying on a backup. From the same release directory,
select the verified backup and create an isolated service-owned data home:

```sh
backup=/var/lib/kos/backups/production-<timestamp>.sqlite3
rehearsal=/var/lib/kos-restore-rehearsal
sudo rm -rf "$rehearsal"
sudo install -d -o kos -g kos -m 0750 "$rehearsal"
sudo install -o kos -g kos -m 0600 "$backup" "$rehearsal/production.sqlite3"
sudo -u kos sh -c '
  set -a; . /etc/kos/kos.env; set +a
  KOS_DATA_HOME=/var/lib/kos-restore-rehearsal PORT=3001 \
    RAILS_ENV=production bundle exec puma -C config/puma.rb
'
```

Leave that foreground process running, and from another terminal check
`http://127.0.0.1:3001/ready` plus a known project or task using the installed
CLI. Do not run `db:prepare` or `db:seed`; they can mutate or mask a bad restore.
Stop Puma with `Ctrl-C`, then remove the rehearsal directory only after success.

To restore after a failure, keep all KOS clients stopped and run from the
verified compatible release:

```sh
sudo systemctl stop kos.service
failed="/var/lib/kos/production.failed-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
sudo mv /var/lib/kos/production.sqlite3 "$failed"
sudo install -o kos -g kos -m 0600 "$backup" /var/lib/kos/production.sqlite3.restore
sudo mv /var/lib/kos/production.sqlite3.restore /var/lib/kos/production.sqlite3
sudo systemctl start kos.service
curl --fail http://127.0.0.1:3000/ready
```

Preserve the failed database for diagnosis. Restart OpenCode and schedulers only
after readiness and a known record both succeed.

## Upgrade And Rollback

Stop Rails, OpenCode, and active schedulers; make and rehearse a backup; then
prepare a new immutable release directory. Rebuild the gem and OpenCode
inventory from that directory. Keep the previous release and worktrees in place
until the rollback decision is closed.
Existing tasks retain their immutable workflow revisions; revisions lacking
`execution_mode` execute as `subagent`, and those lacking `model_tier` execute
as `advanced`. Database preparation installs new canonical built-in revisions
for newly created tasks without repointing existing tasks.

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
bin/install-opencode
sudo -u kos sh -c 'set -a; . /etc/kos/kos.env; set +a; RAILS_ENV=production bin/rails db:prepare'
sudo -u kos sh -c 'set -a; . /etc/kos/kos.env; set +a; RAILS_ENV=production bin/rails db:seed'
```

Before migrations or seeding, switch systemd back to the prior release on
failure. After either command mutates the database, never run the old and new
applications against the same file: stop the service, restore the pre-upgrade
backup, switch to the old release, and require `/ready`. Only then restart
OpenCode and schedulers.

Do not import or dual-run old local `tasks/<id>/<step>.md` files or answer
sidecars. They are not workflow state and remain ignored.

## Check

Run `bin/check` in the release checkout; it proves automated lifecycle and
installed-asset contracts. Separately, required deployment release evidence
uses live models and isolated state and repositories to run real `/kos-brief`,
`/kos`, `/kos-fix`, and `/kos-task` commands through terminal completion. Confirm completed
tasks, released ownership, accepted artifacts in KOS, expected remote commits,
and the brief child graph. Passing `bin/check` alone is not evidence that those
live command executions occurred.
