# Installation

Install the Rails service, CLI gem, built-in catalog, and OpenCode integration
from one checked-out Git revision. Mixed revisions are unsupported because step
context, artifact reporting, profiles, and workflow outcomes are one protocol.

## Prerequisites

- Ruby 3.4.10 and Bundler 4.0.20;
- SQLite 3 with development headers;
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
```

`KOS_DATA_HOME` must be an absolute local path outside the checkout, not a
synchronized or network-mounted directory. Database preparation installs the
canonical `brief`, `development`, and `fix` task types and workflows. It does
not register a project.

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

## Configure And Register

Start Rails with the same data home and token:

```sh
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
bin/rails server
```

In another terminal, expose the same API and installed CLI, verify readiness,
and explicitly register the repository:

```sh
export KOS_DATA_HOME="$HOME/.local/share/kos"
export KOS_API_TOKEN="<installation-token>"
export KOS_API_URL="http://127.0.0.1:3000"
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

`health` uses `KOS_API_URL` to call the public `GET /up` endpoint and does not
require a token. `session-id` is entirely local and requires neither API
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

## Upgrade

Stop Rails and active schedulers, check out one new revision, rebuild and
install the gem, reinstall the OpenCode integration, prepare the existing
database, and restart Rails and OpenCode. Back up persistent state first.
Existing tasks retain their immutable workflow revisions; revisions lacking
`execution_mode` execute as `subagent`, and those lacking `model_tier` execute
as `advanced`. Database preparation installs new canonical built-in revisions
for newly created tasks without repointing existing tasks.

```sh
gem build kos.gemspec --output /tmp/kos.gem
gem install /tmp/kos.gem
bin/install-opencode
bin/rails db:prepare
```

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
